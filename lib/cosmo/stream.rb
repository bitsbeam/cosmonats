# frozen_string_literal: true

require "cosmo/stream/data"
require "cosmo/stream/message"
require "cosmo/stream/processor"
require "cosmo/stream/serializer"

module Cosmo
  module Stream
    def self.included(base)
      base.extend(ClassMethods)
      base.register
    end

    module ClassMethods
      def options(stream: nil, consumer_name: nil, batch_size: nil, consumer: nil, publisher: nil)
        default_options.merge!({ stream: stream, consumer_name: consumer_name, batch_size:, consumer:, publisher: }.compact)
      end

      def publish(data, subject: nil)
        stream = default_options[:stream]
        subject ||= default_options.dig(:publisher, :subject)
        Publisher.publish(subject, data, stream: stream, serializer: default_options.dig(:publisher, :serializer))
      end

      def default_options
        @default_options ||= Utils::Hash.dup(superclass.respond_to?(:default_options) ? superclass.default_options : Data::DEFAULTS)
      end

      def register
        Config.system[:streams] ||= []
        Config.system[:streams] << self

        # settings are inherited, don't try to modify them
        return if default_options != Data::DEFAULTS

        class_name = Utils::String.underscore(name)
        default_options.merge!(stream: class_name,
                               consumer_name: "consumer-#{class_name}",
                               publisher: { subject: "#{class_name}.default" })
        subjects = default_options.dig(:consumer, :subjects)
        subjects&.map! { format(it, name: class_name) }

        subject = default_options[:publisher][:subject]
        default_options[:publisher][:subject] = format(subject, name: class_name)
      end
    end

    def process(messages)
      messages.each { process_one(it) }
    end

    def process_one(...)
      raise NotImplementedError, "#{self.class}#process_one must be implemented"
    end

    def publish
      # TODO: impl
    end
  end
end
