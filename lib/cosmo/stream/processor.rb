# frozen_string_literal: true

module Cosmo
  module Stream
    class Processor < ::Cosmo::Processor
      private

      def setup
        @configs ||= []
        @configs = static_config + dynamic_config

        if @options[:processors]
          pattern = Regexp.new(@options[:processors].map { "\\b#{_1}\\b" }.join("|"))
          @configs.select! { _1[:class].name.match?(pattern) }
        end

        @configs.each { @consumers << subscribe(nil, _1) }
      end

      def process(messages, processor) # rubocop:disable Metrics/AbcSize
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

      def static_config
        Config.dig(:consumers, :streams)&.filter_map do |config|
          next unless (klass = Utils::String.safe_constantize(config[:class]))

          config.merge(class: klass)
        end.to_a
      end

      def dynamic_config
        Config.internal[:streams]&.map { _1.default_options.merge(class: _1) }.to_a
      end

      def subscribe(_stream_name, config)
        processor = config[:class].new
        subjects = config.dig(:consumer, :subjects)
        deliver_policy = Config.deliver_policy(config[:start_position])
        consumer_config, consumer_name = config.values_at(:consumer, :consumer_name)
        subscription = client.subscribe(subjects, consumer_name, consumer_config.merge(deliver_policy))
        [subscription, config, processor]
      end

      def fetch_subjects(config)
        config.dig(:consumer, :subjects)
      end

      def fetch_timeout(config)
        timeout = config[:fetch_timeout].to_f
        if timeout <= 0
          Logger.warn "Ignoring `fetch_timeout: #{timeout}` (causes high CPU usage) with #{Data::DEFAULTS[:fetch_timeout]}s instead"
          timeout = Data::DEFAULTS[:fetch_timeout].to_f
        end

        timeout
      end
    end
  end
end
