# frozen_string_literal: true

module Cosmo
  module API
    class KV
      attr_reader :kv

      def initialize(name, options = nil)
        @name = name
        @options = Hash(options)
        @kv = client.kv(@name, **@options)
      end

      def set(key, value, ttl: nil)
        return kv.put(key, value.to_s) unless ttl

        # Pass ttl: (seconds) to set per-message expiry.
        # Raises `NATS::KeyValue::KeyWrongLastSequenceError` when the key is live.
        publish_cas(key, value.to_s, ttl, last_seq: 0).seq
      end

      def get(key)
        kv.get(key)
      rescue NATS::KeyValue::KeyNotFoundError
        # nop
      end

      # Creates +key+ if it does not already exist -- a plain CAS-if-absent with
      # no per-message TTL involved. Raises NATS::KeyValue::KeyWrongLastSequenceError
      # when the key is already live, so callers can use it as a fire-once gate.
      def create(key, value)
        kv.create(key, value.to_s)
      end

      # Writes a KV-Operation tombstone. On a ttl-bearing bucket this leaves the
      # subject occupied, so a subsequent #set(ttl:) CAS with last_seq: 0 will
      # keep failing -- use #erase on those buckets instead.
      def delete(key)
        kv.delete(key)
      end

      def keys(subject = nil, limit: 25)
        results = []
        watcher = kv.watch(subject || ">", ignore_deletes: true, meta_only: true)
        watcher.each do |entry|
          break unless entry

          results << entry.key
          break if results.size >= limit
        end
        watcher.stop
        results
      end

      # Writes a KV-Operation tombstone (same issue as #delete on ttl buckets).
      def purge(key)
        kv.purge(key)
      end

      # Removes +key+ leaving no trace at all -- unlike #delete/#purge, which
      # write a KV-Operation tombstone message. Mirrors how per-message
      # Nats-TTL expiry removes a key, so callers never have to distinguish
      # "deleted" from "TTL-expired" on read.
      def erase(key)
        client.purge("KV_#{@name}", "$KV.#{@name}.#{key}")
      end

      def clean
        client.purge("KV_#{@name}", ">")
      end

      def count
        keys.size
      rescue NATS::KeyValue::NoKeysFoundError, NATS::JetStream::Error::NotFound
        0
      end
      alias size count

      private

      # CAS = Compare-And-Swap: publish +value+ with a per-message Nats-TTL,
      # but only if the subject's current last sequence matches +last_seq+
      # (sent as the Nats-Expected-Last-Subject-Sequence header). Raises
      # NATS::KeyValue::KeyWrongLastSequenceError if it doesn't match --
      # e.g. last_seq: 0 means "only publish if nothing exists here yet".
      def publish_cas(key, value, ttl, last_seq:)
        headers = { "Nats-Expected-Last-Subject-Sequence" => last_seq.to_s, "Nats-TTL" => "#{ttl.to_i}s" }
        client.js.publish("$KV.#{@name}.#{key}", value, header: headers)
      rescue NATS::JetStream::Error::APIError => e
        raise NATS::KeyValue::KeyWrongLastSequenceError, e.description if e.err_code == 10_071

        raise
      end

      def client
        Client.instance
      end
    end
  end
end
