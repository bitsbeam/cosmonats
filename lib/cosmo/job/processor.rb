# frozen_string_literal: true

module Cosmo
  module Job
    class Processor < ::Cosmo::Processor
      def initialize(pool, running)
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
          @consumers[stream_name] = client.subscribe(subject, consumer_name, config)
        end
      end

      def work_loop
        while running?
          @weights.shuffle.each do |stream_name|
            break unless running?

            begin
              timeout = ENV.fetch("COSMO_JOBS_FETCH_TIMEOUT", 0.1).to_f
              @pool.post { fetch_messages(stream_name, batch_size: 1, timeout:) }
            rescue Concurrent::RejectedExecutionError
              break # pool doesn't accept new jobs, we are shutting down
            end

            break unless running?
          end
        end
      end

      def schedule_loop # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        while running?
          break unless running?

          timeout = ENV.fetch("COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT", 5).to_f
          fetch_messages(:scheduled, batch_size: 100, timeout:) do |messages|
            now = Time.now.to_i
            messages.each do |message|
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

        begin
          sw = stopwatch
          Logger.with(jid: data[:jid])
          Logger.info "start"
          instance = worker_class.new
          instance.jid = data[:jid]
          instance.perform(*data[:args])
          message.ack
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "done" }
        rescue StandardError => e
          Logger.debug e
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail" }
          handle_failure(message, data)
        rescue Exception # rubocop:disable Lint/RescueException
          Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail" }
          raise
        end
      ensure
        Logger.without(:jid)
        Logger.debug "processed message #{message.inspect}"
      end

      def handle_failure(message, data) # rubocop:disable Metrics/AbcSize
        current_attempt = message.metadata.num_delivered
        max_retries = data[:retry].to_i + 1

        if current_attempt < max_retries
          # NATS will auto-retry based on max_deliver with exponential backoff
          delay_ns = ((current_attempt**4) + 15) * 1_000_000_000
          message.nak(delay: delay_ns)
          return
        end

        if data[:dead]
          Client.instance.publish("jobs.dead.#{Utils::String.underscore(data[:class])}", message.data)
          message.ack
          Logger.debug "job moved #{data[:jid]} to DLQ"
        else
          message.term
          Logger.debug "job dropped #{data[:jid]}"
        end
      end
    end
  end
end
