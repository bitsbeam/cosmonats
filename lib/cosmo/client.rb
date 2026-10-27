# frozen_string_literal: true

require "socket"
require "nats/client"

module Cosmo
  class Client
    # Seconds to wait for a JetStream API reply. Override with COSMO_JS_TIMEOUT.
    JS_TIMEOUT = 5
    # Seconds to wait for the TCP connect+handshake. Override with COSMO_CONNECT_TIMEOUT.
    CONNECT_TIMEOUT = 2
    # Reconnect attempts before the connection closes for good; -1 never gives up, so a process outlives a NATS
    # outage. nats-pure lets NATS_MAX_RECONNECT_ATTEMPTS override it.
    MAX_RECONNECT_ATTEMPTS = -1

    # @return [Client]
    def self.instance
      @instance ||= Client.new
    end

    # Labels the connection in `nats server report connections` and /connz, so a
    # misbehaving process can be found without cross-referencing host IPs. Derived from
    # the running program, which separates a web process from a `cosmo` worker on the
    # same host. Override with COSMO_CLIENT_NAME.
    #
    # @return [String]
    def self.default_name
      ENV.fetch("COSMO_CLIENT_NAME") { "cosmo-#{program_name}-#{Socket.gethostname}-#{Process.pid}" }
    end

    # @return [Integer] seconds to wait for a JetStream API reply
    def self.js_timeout
      ENV.fetch("COSMO_JS_TIMEOUT", JS_TIMEOUT).to_i
    end

    # @return [Integer] seconds to wait for the connection to the server
    def self.connect_timeout
      ENV.fetch("COSMO_CONNECT_TIMEOUT", CONNECT_TIMEOUT).to_i
    end

    # $PROGRAM_NAME is "puma 7.2.1 (tcp://...)" under Puma and a path under the CLI.
    # @return [String]
    def self.program_name
      File.basename($PROGRAM_NAME.to_s.split.first.to_s, ".*").gsub(/[^\w.-]/, "")
    end

    attr_reader :nc, :js, :name

    def initialize(nats_url: ENV.fetch("NATS_URL", "nats://localhost:4222"), name: self.class.default_name)
      @name = name
      Logger.debug "Connecting to NATS server at #{nats_url} as #{@name}..."
      @nc = NATS.connect(nats_url, name: @name, connect_timeout: self.class.connect_timeout,
                                   max_reconnect_attempts: MAX_RECONNECT_ATTEMPTS)
      Logger.debug "Connection established"
      @js = @nc.jetstream(timeout: self.class.js_timeout)
    end

    # @param subject [String]
    # @param payload [String]
    # @param params [Hash] JetStream publish options, e.g. +header:+
    # @return [NATS::JetStream::PubAck]
    def publish(subject, payload, **params)
      js.publish(subject, payload, **params)
    end

    # Create a pull subscription. Durable with +consumer_name+, and ephemeral without.
    # @param config [Hash] Consumer config. Ephemeral consumers additionally require
    #   +:stream+ and +:inactive_threshold+ (seconds the consumer survives without a fetch).
    # @param subject [String, Array<String>]
    # @param consumer_name [String, nil]
    # @return [NATS::JetStream::PullSubscription]
    def subscribe(subject, consumer_name, config)
      return js.pull_subscribe(subject, consumer_name, config: config) if consumer_name

      ephemeral_subscribe(subject, config)
    end

    # @param name [String, Symbol]
    # @return [NATS::JetStream::API::StreamInfo]
    def stream_info(name)
      js.stream_info(name)
    end

    # @param name [String, Symbol]
    # @param config [Hash]
    # @return [NATS::JetStream::API::StreamCreateResponse]
    def create_stream(name, config)
      js.add_stream(name: name, **config)
    end

    # @param name [String, Symbol]
    # @param params [Hash]
    # @return [Boolean]
    def delete_stream(name, params = {})
      js.delete_stream(name, params)
    end

    # @param name [String, Symbol]
    # @param config [Hash]
    # @return [NATS::JetStream::API::StreamCreateResponse]
    def update_stream(name, config)
      js.update_stream(name: name, **config)
    end

    # Create/update a stream, falling back to create when there's no stream.
    # @param name [String] Stream name
    # @param config [Hash] Full desired stream configuration
    # @return [NATS::JetStream::API::StreamCreateResponse]
    def setup_stream(name, config)
      update_stream(name, config)
    rescue NATS::JetStream::Error::StreamNotFound
      create_stream(name, config)
    end

    # Return all subjects in +stream_name+ that match +filter+ using NATS's
    # subjects_filter on STREAM.INFO (requires NATS ≥ 2.9).
    # @param stream_name [String]
    # @param filter [String]
    # @return [Array<String>]
    def cron_subjects_in_stream(stream_name, filter)
      payload = Utils::Json.dump({ subjects_filter: filter })
      resp = nc.request("$JS.API.STREAM.INFO.#{stream_name}", payload)
      data = Utils::Json.parse(resp.data, symbolize_names: false)
      (data&.dig("state", "subjects") || {}).keys
    rescue StandardError
      []
    end

    # @return [Array<NATS::JetStream::API::StreamInfo>] every stream's info, as {#stream_info} returns it; empty when
    #   the request fails
    def list_streams
      response = nc.request("$JS.API.STREAM.LIST", "")
      data = Utils::Json.parse(response.data)
      return [] if data.nil? || data[:streams].nil?

      data[:streams].map { NATS::JetStream::API::StreamInfo.new(_1) }
    rescue NATS::Error
      []
    end

    # Marks the stream paused in its metadata, so workers stop fetching from it.
    #
    # @param name [String]
    # @return [void]
    def pause_stream(name)
      config = stream_info(name).config.to_h
      config[:metadata] ||= {}
      config[:metadata][:"_cosmo.paused"] = "true"
      update_stream(name, config)
    end

    # @param name [String]
    # @return [void]
    def unpause_stream(name)
      config = stream_info(name).config.to_h
      config[:metadata] ||= {}
      config[:metadata].delete(:"_cosmo.paused")
      update_stream(name, config)
    end

    # @param name [String]
    # @return [Boolean] false when the server doesn't answer in time
    def stream_paused?(name)
      stream_info(name).config.metadata&.[](:"_cosmo.paused") == "true"
    rescue NATS::IO::Timeout
      false
    end

    # @param stream_name [String]
    # @return [Array<Hash>] the stream's consumers as JetStream reports them
    def list_consumers(stream_name)
      response = nc.request("$JS.API.CONSUMER.LIST.#{stream_name}", "")
      data = Utils::Json.parse(response.data, default: {}, symbolize_names: false)
      Array(data["consumers"])
    end

    # @param stream_name [String]
    # @param consumer_name [String]
    # @return [NATS::JetStream::API::ConsumerInfo]
    def consumer_info(stream_name, consumer_name)
      js.consumer_info(stream_name, consumer_name)
    end

    # @param stream_name [String]
    # @param consumer_name [String]
    # @return [Boolean]
    def delete_consumer(stream_name, consumer_name)
      js.delete_consumer(stream_name, consumer_name)
    end

    # @param stream_name [String, Symbol]
    # @param options [Hash] e.g. +seq:+, or +subject:+ for the last message on it
    # @return [NATS::JetStream::API::RawStreamMsg]
    def get_message(stream_name, **options)
      js.get_msg(stream_name, **options)
    end

    # The last message on every subject matching +filters+, in one batched direct get (NATS ≥ 2.11). Needs
    # +allow_direct+ on the stream.
    #
    # @param stream_name [String]
    # @param filters [Array<String>] subject filters, wildcards allowed
    # @return [Hash{String => String}] message data by subject
    def last_messages(stream_name, filters)
      inbox = nc.new_inbox
      sub = nc.subscribe(inbox)
      nc.publish("$JS.API.DIRECT.GET.#{stream_name}", Utils::Json.dump({ multi_last: filters, batch: 10_000 }), inbox)
      messages = {}
      loop do
        msg = sub.next_msg(timeout: self.class.js_timeout)
        subject = msg.header&.dig(NATS::JetStream::Header::SUBJECT)
        break unless subject

        messages[subject] = msg.data
      end
      messages
    rescue NATS::Timeout
      messages
    ensure
      sub&.unsubscribe
    end

    # @param name [String] the stream
    # @param seq [Integer]
    # @return [Hash] the JetStream API reply
    def delete_message(name, seq)
      response = nc.request("$JS.API.STREAM.MSG.DELETE.#{name}", JSON.dump({ seq: seq }))
      Utils::Json.parse(response.data, symbolize_names: false)
    end

    # Purges +stream_name+, only the messages on +subject+ when given.
    #
    # @param stream_name [String]
    # @param subject [String, nil]
    # @return [Integer] how many messages were purged
    # @raise [NATS::JetStream::Error] when JetStream rejects the purge
    def purge(stream_name, subject)
      payload = subject ? Utils::Json.dump({ filter: subject }) : ""
      response = @nc.request("$JS.API.STREAM.PURGE.#{stream_name}", payload)
      result = Utils::Json.parse(response.data, default: {}, symbolize_names: false)
      raise NATS::JetStream::Error, result.dig("error", "description") if result["error"]

      result["purged"] # number of messages purged
    end

    # Looks up the +name+ KV bucket, creating it with +options+ when it doesn't exist.
    #
    # @param name [String]
    # @param allow_msg_ttl [Boolean] lets the bucket's messages carry their own +Nats-TTL+
    # @param options [Hash] the bucket's config, used only on creation, e.g. +ttl:+
    # @return [NATS::KeyValue]
    def kv(name, allow_msg_ttl: false, **options)
      js.key_value(name)
    rescue NATS::KeyValue::BucketNotFoundError
      allow_msg_ttl ? create_kv_with_msg_ttl(name, **options) : js.create_key_value({ bucket: name }.merge(options))
    end

    # @return [void]
    def close
      nc.close
    end

    private

    # NOTE: nats-pure's #pull_subscribe can't create a true ephemeral pull consumer: its rescue branch
    # unconditionally sets `config[:durable_name] = durable` (jetstream.rb). So the consumer is created
    # here, and #pull_subscribe only binds to it by name.
    def ephemeral_subscribe(subject, config) # rubocop:disable Metrics/AbcSize
      config = config.dup
      stream = config.delete(:stream) or raise ArgumentError, "stream required for ephemeral consumers"
      raise ArgumentError, "inactive_threshold required for ephemeral consumers" unless config[:inactive_threshold]

      subject = subject.first if subject.is_a?(Array) && subject.size == 1
      consumer_config = NATS::JetStream::API::ConsumerConfig.new(config)
      if subject.is_a?(Array)
        consumer_config[:filter_subjects] ||= subject
      else
        consumer_config[:filter_subject] ||= subject
      end

      info = js.add_consumer(stream, consumer_config)
      js.pull_subscribe(subject, nil, stream: stream, name: info.name)
    end

    # NOTE: KV manager in nats-pure hardcodes the fields it copies into StreamConfig,
    # so `allow_msg_ttl` is never forwarded via create_key_value. Send the raw stream-create API request instead.
    def create_kv_with_msg_ttl(name, replicas: 1, **options)
      payload = Utils::Json.dump({
        name: "KV_#{name}",
        subjects: ["$KV.#{name}.>"],
        storage: "file",
        allow_direct: true,
        allow_msg_ttl: true,
        allow_rollup_hdrs: true,
        max_msgs_per_subject: 1,
        num_replicas: replicas
      }.merge(options))
      resp = nc.request("$JS.API.STREAM.CREATE.KV_#{name}", payload)
      result = Utils::Json.parse(resp.data, symbolize_names: false)
      if result&.dig("error")
        msg = result.dig("error", "description").to_s
        # Two worker processes starting simultaneously can both attempt creation.
        # If another process won the race, fall back to looking up the existing bucket.
        raise NATS::JetStream::Error, msg unless msg.match?(/already in use|already exists/i)
      end
      js.key_value(name)
    end
  end
end
