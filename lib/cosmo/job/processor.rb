# frozen_string_literal: true

require "timeout"

module Cosmo
  module Job
    class Processor < ::Cosmo::Processor
      # Headers the scheduler consumes rather than forwards. The +X-+ ones address the dispatch
      # itself, and NATS sets +Nats-Scheduler+/+Nats-Schedule-Next+ on a message it fires and
      # rejects a publish that carries them back.
      DISPATCH_HEADERS = %w[X-Stream X-Subject X-Execute-At Nats-Expected-Stream
                            Nats-Scheduler Nats-Schedule-Next].freeze

      # @raise [UnknownJobStreamError] when --streams/--stream or COSMO_JOBS_STREAMS names an unconfigured stream
      def self.validate_options!(options)
        StreamFilter.from(options[:streams]).validate!
      end

      # @return [Array<String>] job streams pulled from, plus +scheduled+ when dispatching scheduled jobs
      def subscriptions
        names = @consumers.map { |(_, config, _)| config[:stream].to_s }
        names << StreamFilter::SCHEDULED.to_s if scheduler? && scheduled_config
        names
      end

      private

      def setup
        filter = StreamFilter.from(@options[:streams]).validate!

        # Initialize singletons before starting to process messages
        API::Stats::Busy.instance
        API::Stats::Totals.instance
        Limit.instance
        Config.server_middleware

        jobs_config = Config.dig(:consumers, :jobs)
        jobs_config&.each do |stream_name, config|
          next if stream_name == StreamFilter::SCHEDULED # scheduled jobs are handled in schedule_loop
          next unless filter.include?(stream_name)

          @consumers << subscribe(stream_name, config)
        end

        log_subscriptions
      end

      def log_subscriptions
        return if @consumers.empty?

        names = @consumers.map { |(_, config, _)| config[:consumer] }
        names << consumer_name(StreamFilter::SCHEDULED) if scheduler? && scheduled_config
        Logger.info "subscribed: #{names.join(", ")}#{" (scheduler off)" unless scheduler?}"
      end

      def scheduled_config
        Services.scheduled_consumer
      end

      def schedule_loop # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength, Metrics/AbcSize
        config = scheduled_config
        return unless config

        subscription, = subscribe(StreamFilter::SCHEDULED, config)
        while running?
          break unless running?

          now = Time.now.to_i
          timeout = ENV.fetch("COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT", 5).to_f
          messages = fetch(subscription, batch_size: 100, timeout:)
          messages&.each do |message|
            headers = message.header.except(*DISPATCH_HEADERS)
            stream, subject, execute_at = message.header.values_at("X-Stream", "X-Subject", "X-Execute-At")
            headers["Nats-Expected-Stream"] = stream
            scheduler = message.header["Nats-Scheduler"]
            if scheduler
              headers["X-Scheduled-By"] = scheduler
              headers["X-Enqueued-At"] = message.metadata.timestamp.to_f.to_s
            end
            execute_at = execute_at.to_i

            if now >= execute_at
              client.publish(subject, message.data, header: headers)
              message.ack
            else
              message.nak(delay: Config.to_ns(execute_at - now))
            end
          rescue StandardError => e
            # A transient failure here (e.g. a JetStream publish timeout) must not be allowed
            # to escape #each and kill this thread — schedule_loop only runs once per processor,
            # so an unhandled exception would silently stop all future scheduled-job dispatch.
            Logger.error e
            message.nak rescue nil
          end

          break unless running?
        end
      end

      def process(messages, _) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        message = messages.first
        Logger.debug "received messages #{messages.inspect}"
        data = Utils::Json.parse(message.data)
        return reject_message(message, ArgumentError.new("malformed payload")) unless data

        worker_class = Utils::String.safe_constantize(data[:class])
        unless worker_class
          reject_message(message, ArgumentError.new("#{data[:class]} class not found"), data)
          notify_batch(data, success: false)
          return
        end

        begin
          sw = stopwatch
          Logger.with(jid: data[:jid])
          Logger.info "start"

          instance = build_worker(worker_class, data, message)
          Config.server_middleware.invoke(instance, data, message) do
            perform_job(instance, data: data, message: message)
          end

          message.ack
          notify_batch(data, success: true)
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "done" }
        rescue Requeue => e
          message.nak(delay: Config.to_ns(e.delay))
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "requeue[#{e.delay}s]" }
        rescue Timeout::Error => e
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail[timeout]" }
          handle_failure(worker_class, message, data, e)
        rescue StandardError => e
          Logger.debug e
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail[error]" }
          handle_failure(worker_class, message, data, e)
        rescue Exception # rubocop:disable Lint/RescueException
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail[exception]" }
          raise
        end
      ensure
        Logger.without(:jid)
        Logger.debug "processed message #{message.inspect}"
      end

      def build_worker(worker_class, data, message)
        worker_class.new.tap do |worker|
          worker.jid = data[:jid]
          worker.enqueued_at = enqueued_at(message)
          worker.attempt = message.metadata.num_delivered
          worker.scheduled_by = scheduled_by(message)
          worker.batch_id = data[:batch_id]
        end
      end

      def handle_failure(worker_class, message, data, exception) # rubocop:disable Naming/PredicateMethod
        current_attempt = message.metadata.num_delivered
        desired_retries = data[:retry].to_i + 1
        capped_at = deliver_cap(message.metadata.stream, desired_retries)

        if current_attempt < (capped_at || desired_retries)
          nak_message(worker_class, message, data, current_attempt, exception)
          return false
        end

        warn_capped(message, data, capped_at) if capped_at
        data[:dead] ? move_message(message, data, exception) : drop_message(message, data)
        notify_batch(data, success: false)
        true
      end

      def notify_batch(data, success:)
        return unless data[:batch_id]

        Batch.notify(data[:batch_id], data[:jid], success: success)
      end

      # The message is NAK'd with an explicit delay (default backoff, or the job class's own +retry_in+ handler).
      def nak_message(worker_class, message, data, current_attempt, exception)
        message.nak(delay: Config.to_ns(retry_delay(worker_class, data, current_attempt, exception)))
      end

      def warn_capped(message, data, capped_at)
        consumer_name = consumer_entry(message.metadata.stream)&.dig(1, :consumer)
        Logger.warn "#{data[:class]} configured retry: #{data[:retry]} exceeds max_deliver: #{capped_at} " \
                    "on #{consumer_name}; giving up early to avoid a stranded message"
      end

      # Returns the consumer's configured +max_deliver+ when it's lower than the job's own configured
      # retry count (so we should give up a bit early instead of NAK'ing into a redelivery that'll never
      # come), or +nil+ when the job's own retry count is already the binding constraint.
      def deliver_cap(stream_name, desired_retries)
        max_deliver = consumer_entry(stream_name)&.dig(1, :max_deliver).to_i
        max_deliver if max_deliver.positive? && max_deliver < desired_retries
      end

      def consumer_entry(stream_name)
        @consumers.find { |(_, config, _)| config[:stream].to_s == stream_name.to_s }
      end

      def retry_delay(worker_class, data, current_attempt, exception)
        handler = worker_class.retry_in(data)
        return default_retry_delay(current_attempt) unless handler

        delay = handler.call(current_attempt, exception)
        delay.is_a?(Numeric) && delay.positive? ? delay : default_retry_delay(current_attempt)
      rescue StandardError => e
        Logger.error e
        default_retry_delay(current_attempt)
      end

      def default_retry_delay(current_attempt)
        (current_attempt**4) + 15
      end

      def subscribe(stream_name, config)
        config = config.dup
        config[:batch_size] = 1
        config[:stream] = stream_name
        config[:consumer] = consumer_name(stream_name)
        subscription = client.subscribe(config[:subject], config[:consumer], config.except(:subject, :priority, :stream, :batch_size, :consumer))
        [subscription, config, nil]
      end

      def drop_message(message, data)
        message.term
        Logger.debug "job dropped #{data&.dig(:jid)}"
      end

      # Logs why a message can't be processed at all and parks it in the DLQ.
      def reject_message(message, error, data = nil)
        Logger.error error
        move_message(message, data, error)
      end

      def move_message(message, data = nil, exception = nil)
        return drop_message(message, data) unless Config.dead.enabled

        klass = data ? Utils::String.underscore(data[:class]) : "default"
        headers = { "X-Stream" => message.metadata.stream, "X-Subject" => message.subject }
        headers.merge!(Failure.headers(exception)) if exception
        Client.instance.publish("jobs.dead.#{klass}", message.data, header: headers)
        message.ack
        Logger.debug "job moved #{data&.dig(:jid)} to DLQ"
      end

      def scheduler?
        @options.fetch(:scheduler, true)
      end

      # +Nats-Scheduler+ on a message NATS fired directly into a job stream, and +X-Scheduled-By+
      # on one the scheduler dispatched onward, which may not carry the reserved header.
      def scheduled_by(message)
        header = message.header or return

        header["X-Scheduled-By"] || header["Nats-Scheduler"]
      end

      # A cron message is enqueued when NATS fires it, not when the scheduler dispatches it on, so
      # the firing forwards its own timestamp in +X-Enqueued-At+ to survive the re-publish.
      def enqueued_at(message)
        forwarded = message.header&.dig("X-Enqueued-At")

        forwarded ? Time.at(forwarded.to_f) : message.metadata.timestamp
      end

      # Durable and per stream, so every process pulls from the same consumer and shares the work.
      def consumer_name(stream_name)
        "consumer-#{stream_name}"
      end

      def consumers
        @weights ||= @consumers.filter_map { |(_, c, _)| [c[:stream]] * [c[:priority].to_i, 1].max }.flatten
        @weights.shuffle.map { |s| @consumers.find { |(_, c, _)| c[:stream] == s } }
      end

      def fetch_subjects(config)
        config[:subject]
      end

      def fetch_timeout(_config)
        ENV.fetch("COSMO_JOBS_FETCH_TIMEOUT", 0.1).to_f
      end

      # @param job_instance [Cosmo::Job]
      # @param data [Hash]
      # @param message [NATS::Msg]
      #
      # rubocop:disable-next Lint/UnusedMethodArgument
      def perform_job(job_instance, data:, message:)
        job_instance.perform(*data[:args])
      end
    end
  end
end
