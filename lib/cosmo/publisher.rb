# frozen_string_literal: true

require "forwardable"

module Cosmo
  class Publisher
    class << self
      extend Forwardable

      delegate %i[publish] => :instance
    end

    # @return [Publisher]
    def self.instance
      @instance ||= new
    end

    def initialize
      @client = Client.instance
    end

    # Serializes +data+ and publishes it to +subject+.
    #
    # @param subject [String]
    # @param data [Object]
    # @param serializer [#serialize, nil] defaults to {Stream::Serializer}
    # @param options [Hash] JetStream publish options, e.g. +header:+
    # @return [NATS::JetStream::PubAck]
    def publish(subject, data, serializer: nil, **options)
      payload = (serializer || Stream::Serializer).serialize(data)
      @client.publish(subject, payload, **options)
    end
  end
end
