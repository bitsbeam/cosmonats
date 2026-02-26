# frozen_string_literal: true

module Cosmo
  module Stream
    class Processor < ::Cosmo::Processor
      def initialize(pool, running, options)
        super
        @configs = []
      end

      private

      def run_loop
        Thread.new { work_loop }
      end

      def setup
        setup_configs
        setup_consumers
      end

      def work_loop # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
        shutdown = false

        while running?
          break if shutdown

          @consumers.each do |(subscription, config, processor)|
            break unless running?

            begin
              @pool.post do
                timeout = convert_timeout(config[:fetch_timeout])
                Logger.debug "fetching #{config.dig(:consumer, :subjects).inspect}, timeout=#{timeout}"
                messages = fetch(subscription, batch_size: config[:batch_size], timeout:)
                Logger.debug "fetched (#{messages&.size.to_i}) messages"
                process(messages, processor) if messages&.any?
                Logger.debug "processed (#{messages&.size.to_i}) messages"
              end
            rescue Concurrent::RejectedExecutionError
              shutdown = true
              break # pool doesn't accept new jobs, we are shutting down
            end

            break unless running?
          end
        end
      end

      def process(messages, processor) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        metadata = messages.last.metadata
        serializer = processor.class.default_options.dig(:publisher, :serializer)
        messages = messages.map { Message.new(_1, serializer:) }

        Logger.with(
          seq_stream: metadata.sequence.stream,
          seq_consumer: metadata.sequence.consumer,
          num_pending: metadata.num_pending,
          timestamp: metadata.timestamp
        ) { Logger.info "start" }

        sw = stopwatch
        processor.process(messages)
        Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "done" }
      rescue StandardError => e
        Logger.debug e
        Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail" }
      rescue Exception # rubocop:disable Lint/RescueException
        Logger.with(elapsed: sw.elapsed_seconds) { Logger.info "fail" }
        raise
      end

      def setup_configs
        @configs = static_config + dynamic_config
        return unless @options[:processors]

        pattern = Regexp.new(@options[:processors].map { "\\b#{_1}\\b" }.join("|"))
        @configs.select! { _1[:class].name.match?(pattern) }
      end

      def setup_consumers
        @configs.each do |config|
          processor = config[:class].new
          subjects = config.dig(:consumer, :subjects)
          deliver_policy = Config.deliver_policy(config[:start_position])
          consumer_config, consumer_name = config.values_at(:consumer, :consumer_name)
          subscription = client.subscribe(subjects, consumer_name, consumer_config.merge(deliver_policy))
          @consumers << [subscription, config, processor]
        end
      end

      def static_config
        Config.dig(:consumers, :streams)&.filter_map do |config|
          next unless (klass = Utils::String.safe_constantize(config[:class]))

          config.merge(class: klass)
        end.to_a
      end

      def dynamic_config
        Config.system[:streams].map { _1.default_options.merge(class: _1) }
      end

      def convert_timeout(value)
        timeout = value.to_f
        if timeout <= 0
          Logger.warn "Ignoring `fetch_timeout: #{timeout}` (causes high CPU usage) with #{Data::DEFAULTS[:fetch_timeout]}s instead"
          timeout = Data::DEFAULTS[:fetch_timeout].to_f
        end

        timeout
      end
    end
  end
end
