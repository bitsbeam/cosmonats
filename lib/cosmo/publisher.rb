# frozen_string_literal: true

require "forwardable"

module Cosmo
  class Publisher
    class << self
      extend Forwardable

      delegate %i[publish publish_job publish_batch] => :instance
    end

    def self.instance
      @instance ||= new
    end

    def initialize
      @client = Client.instance
    end

    def publish(subject, data, serializer: nil, **options)
      payload = (serializer || Stream::Serializer).serialize(data)
      @client.publish(subject, payload, **options)
      true
    end

    def publish_job(data)
      subject, payload, params = data.to_args
      @client.publish(subject, payload, **params)
      data.jid
    rescue NATS::JetStream::Error::NoStreamResponse
      raise StreamNotFoundError, params[:stream].to_s
    end

    def publish_batch(subject, batch, **options)
      batch.each { publish(subject, it, **options) }
    end
  end
end
