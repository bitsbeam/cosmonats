# frozen_string_literal: true

module Cosmo
  module Utils
    class TTLCache
      def initialize
        @store = {}
      end

      def set(key, value, ttl: nil)
        @store[key] = [value, ttl ? Time.now + ttl : nil]
        value
      end

      def get(key)
        return unless key?(key)

        @store[key].first
      end

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
