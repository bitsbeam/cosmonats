# frozen_string_literal: true

module Cosmo
  class Web
    # A short-lived, process-wide cache of the web UI's refresh responses: requests for the same data, from several
    # open tabs, wait for a single fetch and share its result for TTL seconds, so viewers don't multiply NATS reads.
    class Cache
      # Seconds a response is shared. Override with COSMO_WEB_CACHE_TTL; 0 turns the cache off.
      TTL = 2
      LIMIT = 256

      def self.instance
        @instance ||= new
      end

      def initialize(ttl: ENV.fetch("COSMO_WEB_CACHE_TTL", TTL).to_f)
        @ttl = ttl
        @lock = Mutex.new
        @entries = {}
        @gates = {}
      end

      # @param key [Object]
      # @yieldreturn [Object] the value, computed only when no fresh copy is cached
      # @return [Object]
      def fetch(key)
        return yield unless @ttl.positive?

        gate(key).synchronize do
          entry = read(key)
          next entry.first if entry

          yield.tap { |value| write(key, value) }
        end
      end

      # Forgets every cached value, so the next request reads fresh data.
      #
      # @return [void]
      def clear
        @lock.synchronize { @entries.clear }
      end

      private

      def gate(key)
        @lock.synchronize { @gates[key] ||= Mutex.new }
      end

      def read(key)
        @lock.synchronize do
          entry = @entries[key]
          entry if entry && entry.last > clock
        end
      end

      def write(key, value)
        @lock.synchronize do
          prune if @entries.size >= LIMIT
          @entries[key] = [value, clock + @ttl]
        end
      end

      def prune
        now = clock
        @entries.delete_if { |_, (_, expires)| expires <= now }
        @gates.delete_if { |key, _| !@entries.key?(key) }
      end

      def clock
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end
    end
  end
end
