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

    def update_stream(name, config)
      js.update_stream(name: name, **config)
    end

    def list_streams
      response = nc.request("$JS.API.STREAM.LIST", "")
      data = Utils::Json.parse(response.data, symbolize_names: false)
      return [] if data.nil? || data["streams"].nil?

      data["streams"]
    end

    def pause_stream(name)
      config = stream_info(name).config.to_h
      config[:metadata] ||= {}
      config[:metadata][:"_cosmo.paused"] = "true"
      update_stream(name, config)
    end

    def unpause_stream(name)
      config = stream_info(name).config.to_h
      config[:metadata] ||= {}
      config[:metadata].delete(:"_cosmo.paused")
      update_stream(name, config)
    end

    def stream_paused?(name)
      stream_info(name).config.metadata&.[](:"_cosmo.paused") == "true"
    rescue NATS::IO::Timeout
      false
    end

    def list_consumers(stream_name)
      response = nc.request("$JS.API.CONSUMER.LIST.#{stream_name}", "")
      data = Utils::Json.parse(response.data, default: {}, symbolize_names: false)
      Array(data["consumers"])
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

    def kv(name, allow_msg_ttl: false, **options)
      js.key_value(name)
    rescue NATS::KeyValue::BucketNotFoundError
      allow_msg_ttl ? create_kv_with_msg_ttl(name, **options) : js.create_key_value({ bucket: name }.merge(options))
    end

    def close
      nc.close
    end

    private

    # NOTE: KV manager in nats-pure hardcodes the fields it copies into StreamConfig,
    # so `allow_msg_ttl` is never forwarded via create_key_value. Send the raw stream-create API request instead.
    def create_kv_with_msg_ttl(name, **options)
      payload = Utils::Json.dump({
        name: "KV_#{name}",
        subjects: ["$KV.#{name}.>"],
        storage: "file",
        allow_direct: true,
        allow_msg_ttl: true,
        allow_rollup_hdrs: true,
        max_msgs_per_subject: 1
      }.merge(options))
      resp = nc.request("$JS.API.STREAM.CREATE.KV_#{name}", payload)
      result = Utils::Json.parse(resp.data, symbolize_names: false)
      raise NATS::JetStream::Error, result.dig("error", "description") if result&.dig("error")

      js.key_value(name)
    end
  end
end
