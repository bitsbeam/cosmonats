# frozen_string_literal: true

module Cosmo
  module Job
    # Distributed concurrency limiter backed by NATS Key-Value with per-message TTL.
    #
    # Each unit of concurrency is a numbered KV slot:
    #   "{concurrency_key}/0", "{concurrency_key}/1", ..., "{concurrency_key}/{limit-1}"
    #
    # Acquiring a slot is a single atomic `set` (CAS with last-revision=0).
    # Only one worker can win a given slot; losers try the next number.
    # When a job finishes the slot is deleted; if the worker crashes NATS
    # expires it automatically via the per-message Nats-TTL header.
    class Limit
      BUCKET = "cosmo_jobs_limits"

      def self.instance
        @instance ||= new
      end

      def initialize
        @kv = API::KV.new(BUCKET, allow_msg_ttl: true)
      end

      # Try to acquire one of the numbered slots for +key+.
      #
      # @param key      [String]  concurrency key
      # @param jid      [String]  stored as the slot value for observability
      # @param limit    [Integer] number of slots (0 … limit-1)
      # @param duration [Integer] seconds before the slot is auto-expired by NATS
      # @return [String, nil] the acquired slot key, or nil when all slots are taken
      def acquire(key, jid:, limit:, duration:)
        0.upto(limit - 1) do |i|
          slot = "#{key}/#{i}"
          @kv.set(slot, jid, ttl: duration)
          return slot
        rescue NATS::KeyValue::KeyWrongLastSequenceError
          next # slot is live, try the next one
        end
        nil # all slots occupied
      end

      # Release a previously acquired slot.
      def release(slot)
        @kv.delete(slot)
      rescue StandardError
        # best effort — slot TTL will reclaim it if delete fails
      end
    end
  end
end
