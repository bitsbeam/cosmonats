# frozen_string_literal: true

module Cosmo
  module Utils
    class TTLCache
      def initialize
        @store = {}
      end

      # @param key [Object]
      # @param value [Object]
      # @param ttl [Numeric, nil] seconds until the value expires, nil keeps it forever
      # @return [Object] +value+
      def set(key, value, ttl: nil)
        @store[key] = [value, ttl ? Time.now + ttl : nil]
        value
      end

      # @param key [Object]
      # @return [Object, nil] the value, or nil when it is missing or expired
      def get(key)
        return unless key?(key)

        @store[key].first
      end

      # @param key [Object]
      # @param ttl [Numeric, nil] seconds until a computed value expires
      # @yieldreturn [Object] the value, computed only when no fresh copy is cached
      # @return [Object]
      def fetch(key, ttl: nil)
        return get(key) if key?(key)

        result = yield
        set(key, result, ttl: ttl)
        result
      end

      private

      def key?(key)
        exists = @store.key?(key)
        return false unless exists

        _, ttl = @store[key]
        return true unless ttl
        return true if Time.now < ttl

        @store.delete(key)
        false
      end
    end
  end
end
