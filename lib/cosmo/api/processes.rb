# frozen_string_literal: true

module Cosmo
  module API
    # Registry of live worker processes. Each process overwrites its own entry on every heartbeat,
    # and the bucket's TTL drops the entry of a process that died without unregistering.
    class Processes
      TTL = 60
      LIMIT = 25
      BUCKET = "cosmo_processes"

      def self.instance
        @instance ||= new
      end

      def initialize
        @kv = bucket
      end

      # Writes or refreshes the entry of a process.
      #
      # @param identity [String] a unique process id, e.g. +hostname-pid+
      # @param info [Hash] the process details shown in the Web UI
      # @return [void]
      def register(identity, info)
        @kv.set(key(identity), Utils::Json.dump(info))
      rescue NATS::JetStream::Error::NoStreamResponse
        @kv = bucket
        @kv.set(key(identity), Utils::Json.dump(info))
      end

      # Removes the entry of a process, leaving no tombstone behind.
      #
      # @param identity [String]
      # @return [void]
      def unregister(identity)
        @kv.erase(key(identity))
      end

      # Sorted by host and pid before paging: every heartbeat rewrites an entry, so the bucket's own
      # order shifts constantly and would move processes between pages.
      #
      # @param page [Integer, nil]
      # @param limit [Integer]
      # @return [Array<Hash>] process details, as registered
      def list(page: nil, limit: LIMIT)
        offset = ([page.to_i, 1].max - 1) * limit
        @kv.entries(limit: nil).filter_map { Utils::Json.parse(_1.last) }
           .sort_by { [_1[:hostname].to_s, _1[:pid].to_i] }.slice(offset, limit).to_a
      end

      # @return [Integer] the number of live processes
      def size
        @kv.size
      end

      private

      def bucket
        KV.new(BUCKET, { ttl: TTL })
      end

      def key(identity)
        identity.to_s.gsub(/[^\w.=-]/, "_")
      end
    end
  end
end
