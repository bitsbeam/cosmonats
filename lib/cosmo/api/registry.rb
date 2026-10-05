# frozen_string_literal: true

module Cosmo
  module API
    # Base for a KV bucket of JSON entries that live only while their writer keeps refreshing them:
    # a writer re-puts its entries faster than the bucket's TTL, and an entry whose writer is gone expires.
    # Subclasses define +BUCKET+ and +TTL+.
    class Registry
      LIMIT = 25

      def self.instance
        @instance ||= new
      end

      def initialize
        @kv = bucket
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

      # Removes an entry, leaving no tombstone behind.
      #
      # @param key [String, Integer]
      # @return [void]
      def remove(key)
        @kv.erase(sanitize(key))
      end

      # @param page [Integer, nil]
      # @param limit [Integer]
      # @return [Array<Hash>]
      def list(page: nil, limit: LIMIT)
        offset = ([page.to_i, 1].max - 1) * limit
        @kv.entries(limit:, offset:).filter_map { Utils::Json.parse(_1.last) }
      end

      # @return [Array<Hash>] every live entry
      def all
        @kv.entries(limit: nil).filter_map { Utils::Json.parse(_1.last) }
      end

      # @return [Integer] the number of live entries
      def size
        @kv.size
      end

      private

      def bucket
        KV.new(self.class::BUCKET, { ttl: self.class::TTL })
      end

      def sanitize(key)
        key.to_s.gsub(/[^\w.=-]/, "_")
      end
    end
  end
end
