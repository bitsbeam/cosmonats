# frozen_string_literal: true

require "timeout"

module Cosmo
  module Job
    class Processor < ::Cosmo::Processor
      private

      def setup
        # Initialize singletons before starting to process messages
        API::Busy.instance
        API::Counter.instance
        Limit.instance

        jobs_config = Config.dig(:consumers, :jobs)
        jobs_config&.each do |stream_name, config|
          next if stream_name == :scheduled # scheduled jobs are handled in schedule_loop
          next if @options[:streams] && !@options[:streams].include?(stream_name.to_s)

          @consumers << subscribe(stream_name, config)
        end
      end

      def schedule_loop # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength, Metrics/AbcSize
        config = Config.dig(:consumers, :jobs, :scheduled)
        return unless config

        subscription, = subscribe(:scheduled, config)
        while running?
          break unless running?

          now = Time.now.to_i
          timeout = ENV.fetch("COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT", 5).to_f
          messages = fetch(subscription, batch_size: 100, timeout:)
          messages&.each do |message|
            headers = message.header.except("X-Stream", "X-Subject", "X-Execute-At", "Nats-Expected-Stream")
            stream, subject, execute_at = message.header.values_at("X-Stream", "X-Subject", "X-Execute-At")
            headers["Nats-Expected-Stream"] = stream
            execute_at = execute_at.to_i

            if now >= execute_at
              client.publish(subject, message.data, headers: headers)
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

      def process(messages, _) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        message = messages.first
        Logger.debug "received messages #{messages.inspect}"
        data = Utils::Json.parse(message.data)
        unless data
          Logger.error ArgumentError.new("malformed payload")
          move_message(message)
          return
        end

        worker_class = Utils::String.safe_constantize(data[:class])
        unless worker_class
          Logger.error ArgumentError.new("#{data[:class]} class not found")
          move_message(message, data)
          notify_batch(data, success: false)
          return
        end

        if worker_class.limits_concurrency?
          slot = acquire_concurrency_slot(worker_class, message, data)
          return if slot == false
        end

        duration = worker_class.default_options[:limit]&.dig(:duration)&.to_i

        with_stats(message) do
          sw = stopwatch
          Logger.with(jid: data[:jid])
          Logger.info "start"

          instance = build_worker(worker_class, data, message)
          perform_job(instance, data: data, message: message, duration: duration)

          message.ack
          notify_batch(data, success: true)
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "done" }
          true
        rescue Timeout::Error => e
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail[timeout]" }
          dropped = handle_failure(worker_class, message, data, e)
          false if dropped
        rescue StandardError => e
          Logger.debug e
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail[error]" }
          dropped = handle_failure(worker_class, message, data, e)
          false if dropped
        rescue Exception # rubocop:disable Lint/RescueException
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail[exception]" }
          raise
        end
      ensure
        Limit.instance.release(slot) if slot
        Logger.without(:jid)
        Logger.debug "processed message #{message.inspect}"
      end

      def build_worker(worker_class, data, message)
        worker_class.new.tap do |worker|
          worker.jid = data[:jid]
          worker.enqueued_at = message.metadata.timestamp
          worker.attempt = message.metadata.num_delivered
          worker.scheduled_by = message.header&.dig("Nats-Scheduler")
          worker.batch_id = data[:batch_id]
        end
      end

      # Tries to acquire a concurrency slot for the job.
      # Returns the slot key (String) on success, or false if all slots are
      # taken (a message is NAK'd with a delay of +retry_in+ before returning
      def acquire_concurrency_slot(worker_class, message, data)
        options = worker_class.concurrency_options
        key = worker_class.concurrency_key(data[:args])

        slot = Limit.instance.acquire(key, jid: data[:jid], limit: options[:limit], duration: options[:duration])
        return slot if slot

        message.nak(delay: Config.to_ns(options[:retry_in]))
        Logger.debug "concurrency limit reached for #{data[:class]}, re-queueing back #{data[:jid]}"
        false
      rescue NATS::Error => e
        # Unexpected KV failure (e.g. transient NATS error). NAK immediately so
        # the message is retried rather than stuck in-flight until ack_wait expires.
        Logger.error e
        message.nak
        false
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
        data[:dead] ? move_message(message, data) : drop_message(message, data)
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
        config[:consumer] = "consumer-#{stream_name}"
        subscription = client.subscribe(config[:subject], config[:consumer], config.except(:subject, :priority, :stream, :batch_size, :consumer))
        [subscription, config, nil]
      end

      def drop_message(message, data)
        message.term
        Logger.debug "job dropped #{data[:jid]}"
      end

      def move_message(message, data = nil)
        klass = data ? Utils::String.underscore(data[:class]) : "default"
        headers = { "X-Stream" => message.metadata.stream, "X-Subject" => message.subject }
        Client.instance.publish("jobs.dead.#{klass}", message.data, header: headers)
        message.ack
        Logger.debug "job moved #{data&.dig(:jid)} to DLQ"
      end

      def scheduler?
        true
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

      def with_stats(message, &block)
        API::Busy.instance.with(message) do
          API::Counter.instance.with(&block)
        end
      end

      # @param job_instance [Cosmo::Job]
      # @param data [Hash]
      # @param message [NATS::Msg]
      # @param duration [Float, nil]
      #
      # rubocop:disable Lint/UnusedMethodArgument
      def perform_job(job_instance, data:, message:, duration: nil)
        if duration
          Timeout.timeout(duration) { job_instance.perform(*data[:args]) }
        else
          job_instance.perform(*data[:args])
        end
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end
  end
end
