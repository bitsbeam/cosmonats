# frozen_string_literal: true

module Cosmo
  module Job
    class Processor
      def self.run(...)
        new(...).tap(&:run)
      end

      def initialize(pool, running)
        @pool = pool
        @running = running
        @consumers = {}
        @weights = []
      end

      def run
        setup
        return unless @consumers.any?

        @running.make_true
        Thread.new { work_loop }
        Thread.new { schedule_loop }
      end

      private

      def setup
        jobs_config = Config.dig(:consumers, :jobs)
        jobs_config&.each do |stream_name, config|
          consumer_name = "consumer-#{stream_name}"
          subject = config.delete(:subject)
          priority = config.delete(:priority)
          @weights += ([stream_name] * priority.to_i) if priority
          @consumers[stream_name] = Client.instance.stream.pull_subscribe(subject, consumer_name, config: config)
        end
      end

      def work_loop(timeout: ENV.fetch("COSMO_JOBS_FETCH_TIMEOUT", 0.1).to_f)
        while @running
          @weights.shuffle.each do |name|
            break unless @running.true?

            begin
              message = @consumers[name].fetch(1, timeout: timeout)
              @pool.post { process(message.first) }
            rescue NATS::Timeout
              # No messages, continue
            rescue StandardError => e
              Logger.debug e
            rescue Exception => e # rubocop:disable Lint/RescueException, Lint/DuplicateBranch
              Logger.debug e # Unexpected error!
            end

            break unless @running.true?
          end
        end
      end

      def schedule_loop(timeout: ENV.fetch("COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT", 5).to_f)
        while @running
          break unless @running.true?

          begin
            now = Time.now.to_i
            messages = @consumers[:scheduled].fetch(100, timeout: timeout)
            messages.each do |message|
              headers = message.header.except("X-Stream", "X-Subject", "X-Execute-At", "Nats-Expected-Stream")
              stream, subject, execute_at = message.header.values_at("X-Stream", "X-Subject", "X-Execute-At")
              headers["Nats-Expected-Stream"] = stream
              execute_at = execute_at.to_i

              if now >= execute_at
                Client.instance.publish(subject, message.data, headers: headers)
                message.ack
              else
                delay_ns = (execute_at - now) * 1_000_000_000
                message.nak(delay: delay_ns)
              end
            end
          rescue NATS::Timeout
            # No messages, continue
          end

          break unless @running.true?
        end
      end

      def process(message)
        Logger.debug "received message #{message.inspect}"
        data = Utils::Json.parse(message.data)
        Logger.debug ArgumentError.new("malformed payload") and return unless data

        worker_class = Utils::String.safe_constantize(data[:class])
        Logger.debug ArgumentError.new("#{data[:class]} class not found") and return unless worker_class

        begin
          Logger.with(jid: data[:jid])
          Logger.info "start"
          sw = Utils::Stopwatch.new
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

      def handle_failure(message, data)
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
