# frozen_string_literal: true

module Cosmo
  module Stream
    class Processor
      def self.run(...)
        new(...).tap(&:run)
      end

      def initialize(pool, running)
        @pool = pool
        @running = running
        @consumers = {}
        @configs = {}
        @processors = {}
      end

      def run
        setup
        return unless @consumers.any?

        @running.make_true
        Thread.new { work_loop }
      end

      private

      def setup
        setup_configs
        setup_processors

        @configs.each do |stream_name, config|
          subjects = config.dig(:consumer, :subjects)
          config, consumer_name = config.values_at(:consumer, :consumer_name)
          @consumers[stream_name] = Client.instance.stream.pull_subscribe(subjects, consumer_name, config: config)
        end
      end

      def work_loop(timeout: ENV.fetch("COSMO_STREAMS_FETCH_TIMEOUT", 0.1).to_f)
        while @running
          @consumers.each do |stream_name, consumer|
            break unless @running.true?

            begin
              messages = consumer.fetch(@configs[stream_name][:batch_size], timeout: timeout)
              @pool.post { process_job(@processors[stream_name], messages) }
            rescue Concurrent::RejectedExecutionError
              break # pool doesn't accept new jobs, exiting
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

      def process_job(processor, messages)
        serializer = processor.class.default_options.dig(:publisher, :serializer)
        messages = messages.map { |it| Message.new(it, serializer:) }
        processor.process(messages)
      end

      def setup_configs
        @configs.merge!(
          Config.dig(:consumers, :streams).to_h {
            klass = Utils::String.safe_constantize(it[:class])
            [it[:stream].to_sym, klass ? it.merge(class: klass) : nil]
          }.compact
        )
        @configs.merge!(
          Config.system[:streams].to_h {
            [it.default_options[:stream].to_sym, it.default_options.merge(class: it)]
          }
        )
      end

      def setup_processors
        @configs.each { |s, c| @processors[s] = c[:class].new }
      end
    end
  end
end
