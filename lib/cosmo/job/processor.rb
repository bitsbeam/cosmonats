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
              delay_ns = (execute_at - now) * 1_000_000_000
              message.nak(delay: delay_ns)
            end
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
          instance = worker_class.new
          instance.jid = data[:jid]
          if duration
            Timeout.timeout(duration) { instance.perform(*data[:args]) }
          else
            instance.perform(*data[:args])
          end
          message.ack
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "done" }
          true
        rescue Timeout::Error
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail[timeout]" }
          dropped = handle_failure(message, data)
          false if dropped
        rescue StandardError => e
          Logger.debug e
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail[error]" }
          dropped = handle_failure(message, data)
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

      # Tries to acquire a concurrency slot for the job.
      # Returns the slot key (String) on success, or false if all slots are
      # taken (message is NAK'd with a delay equal to +duration+ before returning).
      def acquire_concurrency_slot(worker_class, message, data)
        options = worker_class.concurrency_options
        key = worker_class.concurrency_key(data[:args])

        slot = Limit.instance.acquire(key, jid: data[:jid], limit: options[:limit], duration: options[:duration])
        return slot if slot

        message.nak(delay: options[:duration] * Config::NANO)
        Logger.debug "concurrency limit reached for #{data[:class]}, re-queueing back #{data[:jid]}"
        false
      rescue NATS::Error => e
        # Unexpected KV failure (e.g. transient NATS error). NAK immediately so
        # the message is retried rather than stuck in-flight until ack_wait expires.
        Logger.error e
        message.nak
        false
      end

      def handle_failure(message, data) # rubocop:disable Naming/PredicateMethod
        current_attempt = message.metadata.num_delivered
        max_retries = data[:retry].to_i + 1

        if current_attempt < max_retries
          # NATS will auto-retry with delay (exponential backoff based on current attempt).
          # When max_deliver is reached, NATS stops redelivering the message and marks it as "max deliveries exceeded".
          # The message is effectively abandoned by NATS — it stays in the stream (consuming a slot) but will never be delivered again to that consumer.
          delay_ns = ((current_attempt**4) + 15) * Config::NANO
          message.nak(delay: delay_ns)
          return false
        end

        data[:dead] ? move_message(message, data) : drop_message(message, data)
        true
      end

      def subscribe(stream_name, config)
        config = config.dup
        config[:batch_size] = 1
        config[:stream] = stream_name
        consumer_name = "consumer-#{stream_name}"
        subscription = client.subscribe(config[:subject], consumer_name, config.except(:subject, :priority, :stream, :batch_size))
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
    end
  end
end
