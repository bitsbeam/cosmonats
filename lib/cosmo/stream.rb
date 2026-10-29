# frozen_string_literal: true

require "cosmo/stream/data"
require "cosmo/stream/message"
require "cosmo/stream/processor"
require "cosmo/stream/serializer"

module Cosmo
  module Stream
    # @param base [Class] the stream class including Stream
    # @return [void]
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Registers the class as a stream processor and merges the given options over its defaults.
      #
      # @param stream [Symbol, String, nil] NATS stream to consume
      # @param consumer_name [String, nil] durable consumer name
      # @param batch_size [Integer, nil] messages fetched per batch
      # @param fetch_timeout [Numeric, nil] seconds to wait for a batch
      # @param start_position [Symbol, String, Time, nil] where a new consumer starts delivering from
      # @param consumer [Hash, nil] consumer config, e.g. +subjects:+
      # @param publisher [Hash, nil] publisher config: +subject:+ and +serializer:+
      # @return [Hash{Symbol => Object}] the class's merged options
      def options(stream: nil, consumer_name: nil, batch_size: nil, fetch_timeout: nil, start_position: nil, consumer: nil, publisher: nil)
        register
        default_options.merge!({ stream:, consumer_name:, batch_size:, fetch_timeout:, start_position:, consumer:, publisher: }.compact)
      end
      alias cosmo_options options

      # @param data [Object] serialized with the publisher's serializer
      # @param subject [String, nil] defaults to the publisher's subject
      # @param options [Hash] passed on to the JetStream publish
      # @return [NATS::JetStream::PubAck]
      def publish(data, subject: nil, **options)
        stream = default_options[:stream]
        subject ||= default_options.dig(:publisher, :subject)
        Publisher.publish(subject, data, stream: stream, serializer: default_options.dig(:publisher, :serializer), **options)
      end

      # Options inherited from the superclass stream, or the built-in defaults.
      #
      # @return [Hash{Symbol => Object}]
      def default_options
        @default_options ||= Utils::Hash.dup(superclass.respond_to?(:default_options) ? superclass.default_options : Data::DEFAULTS)
      end

      # Adds the class to the processed streams and derives its stream, consumer and subjects from its name.
      #
      # @return [void]
      def register
        Config.internal[:streams] ||= []
        Config.internal[:streams] << self

        # settings are inherited, don't try to modify them
        return if default_options != Data::DEFAULTS

        class_name = Utils::String.underscore(name)
        default_options.merge!(stream: class_name,
                               consumer_name: "consumer-#{class_name}",
                               publisher: { subject: "#{class_name}.default" })
        subjects = default_options.dig(:consumer, :subjects)
        subjects&.map! { format(_1, name: class_name) }

        subject = default_options[:publisher][:subject]
        default_options[:publisher][:subject] = format(subject, name: class_name)
      end
    end

    # Calls {#process_one} for each message, exposing it through {#message}.
    #
    # @param messages [Array<Message>]
    # @return [void]
    def process(messages)
      messages.each do |message|
        Thread.current[:cosmo_message] = message
        process_one
      ensure
        Thread.current[:cosmo_message] = nil
      end
    end
    alias process_many process
    alias process_batch process

    # @return [void]
    # @raise [NotImplementedError] unless the stream class overrides it or {#process}
    def process_one
      raise NotImplementedError, "#{self.class}#process_one must be implemented"
    end

    # @return [::Logger]
    def logger
      Logger.instance
    end

    # @return [Message, nil] the message being processed by {#process_one}
    def message
      Thread.current[:cosmo_message]
    end

    # @param data [Object] serialized with the publisher's serializer
    # @param subject [String, nil] defaults to the publisher's subject
    # @param options [Hash] passed on to the JetStream publish
    # @return [NATS::JetStream::PubAck]
    def publish(data, subject, **options)
      self.class.publish(data, subject:, **options)
    end
  end
end
