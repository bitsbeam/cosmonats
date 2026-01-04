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
              @pool.post { process_job(message.first) }
            rescue NATS::Timeout
              # No messages, continue
            rescue StandardError => e
              puts "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
            rescue Exception => e # rubocop:disable Lint/RescueException, Lint/DuplicateBranch
              # Unexpected error!
              puts "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
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

      def process_job(message)
        puts "#perform start #{message.inspect}"
        data = Utils::Json.parse(message.data)
        raise ArgumentError, "malformed payload" unless data

        worker_class = Utils::String.safe_constantize(data[:class])
        raise ArgumentError, "#{data[:class]} class not found" unless worker_class

        Thread.current[:cosmo_jid] = data[:jid]
        worker_class.new.perform(*data[:args])
        message.ack
      rescue StandardError => e
        handle_failure(message, data, e)
      ensure
        Thread.current[:cosmo_jid] = nil
        puts "#perform end #{message.inspect}"
      end

      def handle_failure(message, data, error)
        puts "Error happened for #{data.inspect} with #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}"
        current_attempt = message.metadata.num_delivered
        max_retries = data[:retry].to_i + 1

        if current_attempt >= max_retries
          if data[:dead]
            Client.instance.publish("jobs.dead.#{Utils::String.underscore(data[:class])}", message.data)
            message.ack
          else
            message.term
          end
          puts "Job #{data[:jid]} failed permanently with #{error.class}: #{error.message}"
        else
          # NATS will auto-retry based on max_deliver
          # NATS handles retry automatically with exponential backoff
          delay_ns = ((current_attempt**4) + 15) * 1_000_000_000
          message.nak(delay: delay_ns)
        end
      end
    end
  end
end
