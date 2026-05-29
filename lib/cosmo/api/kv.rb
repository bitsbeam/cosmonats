# frozen_string_literal: true

module Cosmo
  module API
    class KV
      attr_reader :kv

      def initialize(name, options = nil)
        @name = name
        @options = Hash(options)
        @kv = Client.instance.kv(@name, **@options)
      end

      def set(key, value, ttl: nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        return kv.put(key, value.to_s) unless ttl

        # Pass ttl: (seconds) to set a per-message expiry.
        # Raises `NATS::KeyValue::KeyWrongLastSequenceError` when the key is live.
        begin
          value = value.to_s
          put = lambda do |last_seq:|
            headers = { "Nats-Expected-Last-Subject-Sequence" => last_seq.to_s, "Nats-TTL" => "#{ttl.to_i}s" }
            Client.instance.js.publish("$KV.#{@name}.#{key}", value, header: headers)
          rescue NATS::JetStream::Error::APIError => e
            raise NATS::KeyValue::KeyWrongLastSequenceError, e.description if e.err_code == 10_071

            raise
          end

          put.call(last_seq: 0)
          kv.send(:_get, key) # fetch the created entry to get its revision
        rescue NATS::KeyValue::KeyWrongLastSequenceError
          # `kv.get` converts KeyDeletedError → KeyNotFoundError, hiding tombstone info.
          # Use private _get instead — it raises KeyDeletedError with the entry's revision
          begin
            kv.send(:_get, key)
          rescue NATS::KeyValue::KeyDeletedError => e
            put.call(last_seq: e.entry.revision)
            return kv.send(:_get, key)
          end

          raise
        end
      end

      def get(key)
        kv.get(key)
      rescue NATS::KeyValue::KeyNotFoundError
        # nop
      end

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

      def purge(key)
        kv.purge(key)
      end

      def clean
        Client.instance.purge("KV_#{@name}", ">")
      end

      def count
        keys.size
      rescue NATS::KeyValue::NoKeysFoundError, NATS::JetStream::Error::NotFound
        0
      end
      alias size count
    end
  end
end
