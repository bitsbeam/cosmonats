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
          deliver_policy = Config.deliver_policy(config[:start_position])
          config, consumer_name = config.values_at(:consumer, :consumer_name)
          @consumers[stream_name] = Client.instance.stream.pull_subscribe(subjects, consumer_name, config: config.merge(deliver_policy))
        end
      end

      def work_loop(timeout: ENV.fetch("COSMO_STREAMS_FETCH_TIMEOUT", 0.1).to_f)
        while @running
          @consumers.each do |stream_name, consumer|
            break unless @running.true?

            begin
              messages = consumer.fetch(@configs[stream_name][:batch_size], timeout: timeout)
              @pool.post { process(@processors[stream_name], messages) }
            rescue Concurrent::RejectedExecutionError
              break # pool doesn't accept new jobs, exiting
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

      def process(processor, messages)
        metadata = messages.last.metadata
        serializer = processor.class.default_options.dig(:publisher, :serializer)
        messages = messages.map { |it| Message.new(it, serializer:) }

        Logger.with(
          seq_stream: metadata.sequence.stream,
          seq_consumer: metadata.sequence.consumer,
          num_pending: metadata.num_pending,
          timestamp: metadata.timestamp
        ) { Logger.info "start" }

        sw = Utils::Stopwatch.new
        processor.process(messages)
        Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "done" }
      rescue StandardError => e
        Logger.debug e
        Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail" }
      rescue Exception => e # rubocop:disable Lint/RescueException
        Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail" }
        raise
      ensure
        Thread.current[:cosmo_elapsed] = nil
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
