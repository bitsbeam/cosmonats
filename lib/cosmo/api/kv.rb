# frozen_string_literal: true

module Cosmo
  module API
    class KV
      def initialize(name, options = nil)
        @name = name
        @options = Hash(options)
      end

      def set(key, value)
        kv.put(key, value.to_s)
      end

      def get(key)
        kv.get(key).value
      rescue NATS::KeyValue::KeyNotFoundError
        # nop
      end

      def delete(key)
        kv.delete(key)
      end

      def keys(subject = nil, limit: 25)
        results = []
        params = { ignore_deletes: true, meta_only: true }
        watcher = kv.watch(subject || ">", params)

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
      rescue NATS::KeyValue::NoKeysFoundError
        0
      end
      alias size count

      private

      def kv
        @kv ||= Client.instance.kv(@name, **@options)
      end
    end
  end
end
