# frozen_string_literal: true

require "nats/client"
require "cosmo/utils/overrides"

module Cosmo
  class Client
    def self.instance
      @instance ||= Client.new
    end

    attr_reader :nc, :js

    def initialize(nats_url: ENV.fetch("NATS_URL", "nats://localhost:4222"))
      Logger.debug "Connecting to NATS server at #{nats_url}..."
      @nc = NATS.connect(nats_url)
      Logger.debug "Connection established"
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

      data["streams"].filter_map { _1.dig("config", "name") }
    end

    def pause_stream(name)
      list_consumers(name).each { pause_consumer(name, _1["name"], true) }
    end

    def unpause_stream(name)
      list_consumers(name).each { pause_consumer(name, _1["name"], false) }
    end

    def stream_paused?(name)
      consumers = list_consumers(name)
      return false if consumers.empty?

      consumers.all? { _1["paused"] == true }
    rescue NATS::IO::Timeout
      false
    end

    def list_consumers(stream_name)
      response = nc.request("$JS.API.CONSUMER.LIST.#{stream_name}", "")
      data = Utils::Json.parse(response.data, default: {}, symbolize_names: false)
      Array(data["consumers"])
    end

    def pause_consumer(stream_name, consumer_name, paused)
      subject = "$JS.API.CONSUMER.PAUSE.#{stream_name}.#{consumer_name}"
      pause_until = (Time.now + (10 * 60 * 60 * 24 * 365)).utc.iso8601 # 10 years
      payload = paused ? Utils::Json.dump({ pause_until: pause_until }) : "{}"
      response = nc.request(subject, payload)
      result = Utils::Json.parse(response.data, default: {}, symbolize_names: false)
      raise NATS::JetStream::Error, result.dig("error", "description") if result["error"]

      result
    end

    def consumer_info(stream_name, consumer_name)
      js.consumer_info(stream_name, consumer_name)
    end

    def get_message(name, **options)
      js.get_msg(name, **options)
    end

    def delete_message(name, seq)
      response = nc.request("$JS.API.STREAM.MSG.DELETE.#{name}", JSON.dump({ seq: seq }))
      Utils::Json.parse(response.data, symbolize_names: false)
    end

    def purge(stream_name, subject)
      payload = subject ? Utils::Json.dump({ filter: subject }) : ""
      response = @nc.request("$JS.API.STREAM.PURGE.#{stream_name}", payload)
      result = Utils::Json.parse(response.data, default: {}, symbolize_names: false)
      raise NATS::JetStream::Error, result.dig("error", "description") if result["error"]

      result["purged"] # number of messages purged
    end

    def kv(name, **options)
      js.key_value(name)
    rescue NATS::KeyValue::BucketNotFoundError
      js.create_key_value({ bucket: name }.merge(options))
    end

    def close
      nc.close
    end
  end
end
