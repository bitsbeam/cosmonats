# frozen_string_literal: true

module Cosmo
  module API
    module Stats
      # Live worker processes, one entry per process, refreshed by Cosmo::Heartbeat.
      #
      # An entry's key is +<kind>.<host>.<pid>.<concurrency>+: the sorted keys are the stable order to page by (a
      # heartbeat rewrites an entry, so the bucket's own order shifts constantly), and they alone give the process
      # count and the fleet's thread count, so only a page's worth of entries is ever read.
      class Processes < Registry
        TTL = 60
        BUCKET = "_cosmoprocesses"
        KINDS = %w[jobs streams jobs+streams none].freeze

        # Which processors a process is pulling for, judged by its non-empty subscriptions.
        #
        # @param process [Hash]
        # @return [String] one of {KINDS}
        def self.kind(process)
          types = Hash(process[:subscriptions]).reject { |_, names| Array(names).empty? }.keys.map(&:to_s).sort
          types.empty? ? "none" : types.join("+")
        end

        def initialize
          super
          @registered = {}
        end

        # @return [Integer] the worker threads across every live process
        def threads
          keys.sum { _1.split(".").last.to_i }
        end

        # @param identity [String] a unique process id, e.g. +hostname-pid+
        # @param info [Hash] the process details shown in the Web UI
        # @return [void]
        def register(identity, info)
          key = key_for(identity, info)
          put(key, info)
          stale = @registered[identity]
          @registered[identity] = key
          remove(stale) if stale && stale != key
        end

        # @param identity [String]
        # @return [void]
        def unregister(identity)
          key = @registered.delete(identity)
          remove(key) if key
        end

        private

        def key_for(identity, info)
          kind = KINDS.index(self.class.kind(info))
          host = Registry.token(info[:hostname] || identity)
          [kind, host, format("%08d", info[:pid].to_i), info[:concurrency].to_i].join(".")
        end
      end
    end
  end
end
