# frozen_string_literal: true

require "forwardable"

module Cosmo
  class Publisher
    class << self
      extend Forwardable

      delegate %i[publish] => :instance
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
    end
  end
end
