# frozen_string_literal: true

module Cosmo
  module API
    # Base for a KV bucket of JSON entries that live only while their writer keeps refreshing them:
    # a writer re-puts its entries faster than the bucket's TTL, and an entry whose writer is gone expires.
    # Subclasses define +BUCKET+ and +TTL+.
    #
    # An entry's key is what the Web UI counts and pages by: the server counts keys and lists them sorted, so only
    # the entries on the page being shown are ever read.
    class Registry
      LIMIT = 25
      KEYS_TTL = 2

      # @return [Registry]
      def self.instance
        @instance ||= new
      end

      # Makes +value+ one subject token: a key is a dotted path that NATS filters by token.
      #
      # @param value [#to_s]
      # @return [String]
      def self.token(value)
        value.to_s.gsub(/[^\w=-]/, "_").then { _1.empty? ? "_" : _1 }
      end

      def initialize
        @kv = bucket
        @keys_mutex = Mutex.new
      end

      # Writes or refreshes an entry, recreating the bucket if it was deleted under a running writer.
      #
      # @param key [String, Integer]
      # @param value [Hash]
      # @return [void]
      def put(key, value)
        @kv.set(sanitize(key), Utils::Json.dump(value))
      rescue NATS::JetStream::Error::NoStreamResponse
        @kv = bucket
        @kv.set(sanitize(key), Utils::Json.dump(value))
      end

      # Writes or refreshes several entries in one round trip, recreating the bucket like {#put}.
      #
      # @param entries [Hash{String => Hash}] the value by key
      # @return [void]
      def put_many(entries)
        pairs = entries.to_h { |key, value| [sanitize(key), Utils::Json.dump(value)] }
        @kv.write_many(pairs)
      rescue NATS::JetStream::Error::NoStreamResponse
        @kv = bucket
        @kv.write_many(pairs)
      end

      # Removes an entry, leaving no tombstone behind.
      #
      # @param key [String, Integer]
      # @return [void]
      def remove(key)
        @kv.erase(sanitize(key))
      end

      # @param page [Integer, nil]
      # @param limit [Integer]
      # @return [Array<Hash>] the entries on the page, in key order, read in one batched get
      def list(page: nil, limit: LIMIT)
        offset = ([page.to_i, 1].max - 1) * limit
        page_keys = keys.slice(offset, limit).to_a
        @kv.direct_values(page_keys).values_at(*page_keys).filter_map { _1 && Utils::Json.parse(_1) }
      end

      # Read by direct gets rather than a KV watch, so a read costs the same however often the writers refresh.
      #
      # @return [Array<Hash>] every live entry
      def all
        @kv.direct_entries.filter_map { Utils::Json.parse(_1.last) }
      end

      # @return [Integer] the number of live entries, counted by the server
      def size
        keys.size
      end

      private

      def keys
        @keys_mutex.synchronize do
          now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          unless @keys && now - @keys_at < self.class::KEYS_TTL
            @keys = @kv.direct_keys.freeze
            @keys_at = now
          end
          @keys
        end
      end

      def bucket
        KV.new(self.class::BUCKET, { ttl: self.class::TTL, replicas: Config.services.num_replicas })
      end

      def sanitize(key)
        key.to_s.gsub(/[^\w.=-]/, "_")
      end
    end
  end
end
