# frozen_string_literal: true

require "nats/client"

module Cosmo
  class Client
    def self.instance
      @instance ||= Client.new
    end

    attr_reader :nc, :js

    def initialize(nats_url: ENV.fetch("NATS_URL", "nats://localhost:4222"))
      @nc = NATS.connect(nats_url)
      @js = @nc.jetstream
    end

    def publish(subject, payload, **params)
      js.publish(subject, payload, **params)
    end

    def subscribe(subject, consumer_name, config)
      js.pull_subscribe(subject, consumer_name, config: config)
    end

    def stream_info(name)
      js.stream_info(name)
    end

    def create_stream(name, config)
      js.add_stream(name: name, **config)
    end

    def delete_stream(name, params = {})
      js.delete_stream(name, params)
    end

    def list_streams
      response = nc.request("$JS.API.STREAM.LIST", "")
      data = Utils::Json.parse(response.data, symbolize_names: false)
      return [] if data.nil? || data["streams"].nil?

      data["streams"].filter_map { it.dig("config", "name") }
    end

    def get_message(name, seq)
      js.get_msg(name, seq: seq)
    end

    def close
      nc.close
    end
  end
end
