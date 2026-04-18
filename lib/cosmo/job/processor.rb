# frozen_string_literal: true

module Cosmo
  module Job
    class Processor < ::Cosmo::Processor # rubocop:disable Metrics/ClassLength
      def initialize(pool, running, options)
        super
        @weights = []
      end

      private

      def run_loop
        Thread.new { work_loop }
        Thread.new { schedule_loop }
      end

      def setup
        jobs_config = Config.dig(:consumers, :jobs)
        jobs_config&.each do |stream_name, config|
          consumer_name = "consumer-#{stream_name}"
          subject = config.delete(:subject)
          priority = config.delete(:priority)
          @weights += ([stream_name] * priority.to_i) if priority
          subscription = client.subscribe(subject, consumer_name, config)
          @consumers << [subscription, stream_name]
        end
      end

      def work_loop # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength, Metrics/AbcSize
        shutdown = false

        while running?
          break if shutdown

          @weights.shuffle.each do |stream_name|
            break unless running?

            begin
              timeout = ENV.fetch("COSMO_JOBS_FETCH_TIMEOUT", 0.1).to_f
              @pool.post do
                subscription = @consumers.find { |(_, sn)| sn == stream_name }&.first
                messages = lock(stream_name) { fetch(subscription, batch_size: 1, timeout:) }
                process(messages) if messages&.any?
              end
            rescue Concurrent::RejectedExecutionError
              shutdown = true
              break # pool doesn't accept new jobs, we are shutting down
            end

            break unless running?
          end
        end
      end

      def schedule_loop # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength, Metrics/AbcSize
        while running?
          break unless running?

          now = Time.now.to_i
          timeout = ENV.fetch("COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT", 5).to_f
          subscription = @consumers.find { |(_, sn)| sn == :scheduled }&.first
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

      def process(messages) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        message = messages.first
        Logger.debug "received messages #{messages.inspect}"
        data = Utils::Json.parse(message.data)
        unless data
          Logger.debug ArgumentError.new("malformed payload")
          return
        end

        worker_class = Utils::String.safe_constantize(data[:class])
        unless worker_class
          Logger.debug ArgumentError.new("#{data[:class]} class not found")
          return
        end

        with_stats(message) do
          sw = stopwatch
          Logger.with(jid: data[:jid])
          Logger.info "start"
          instance = worker_class.new
          instance.jid = data[:jid]
          instance.perform(*data[:args])
          message.ack
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "done" }
          true
        rescue StandardError => e
          Logger.debug e
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail" }
          dropped = handle_failure(message, data)
          false if dropped
        rescue Exception # rubocop:disable Lint/RescueException
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail" }
          raise
        end
      ensure
        Logger.without(:jid)
        Logger.debug "processed message #{message.inspect}"
      end

      def handle_failure(message, data) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Naming/PredicateMethod
        current_attempt = message.metadata.num_delivered
        max_retries = data[:retry].to_i + 1

        if current_attempt < max_retries
          # NATS will auto-retry based on max_deliver with exponential backoff
          delay_ns = ((current_attempt**4) + 15) * 1_000_000_000
          message.nak(delay: delay_ns)
          return false
        end

        if data[:dead]
          headers = { "X-Stream" => message.metadata.stream, "X-Subject" => message.subject }
          Client.instance.publish("jobs.dead.#{Utils::String.underscore(data[:class])}", message.data, header: headers)
          message.ack
          Logger.debug "job moved #{data[:jid]} to DLQ"
        else
          message.term
          Logger.debug "job dropped #{data[:jid]}"
        end

        true
      end

      def with_stats(message, &block)
        API::Busy.instance.with(message) do
          API::Counter.instance.with(&block)
        end
      end

      def lock(stream_name, &)
        @mutexes ||= Hash.new { |h, k| h[k] = Mutex.new }
        @mutexes[stream_name].synchronize(&)
      end
    end
  end
end
