# frozen_string_literal: true

module Cosmo
  module API
    module Stats
      # Live worker processes, one entry per process, refreshed by Cosmo::Heartbeat.
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

        # Sorted by kind, host and pid before paging: every heartbeat rewrites an entry, so the bucket's own
        # order shifts constantly and would move processes between pages, and each kind stays contiguous.
        #
        # @param page [Integer, nil]
        # @param limit [Integer]
        # @return [Array<Hash>]
        def list(page: nil, limit: LIMIT)
          offset = ([page.to_i, 1].max - 1) * limit
          all.sort_by { [KINDS.index(self.class.kind(_1)) || KINDS.size, _1[:hostname].to_s, _1[:pid].to_i] }.slice(offset, limit).to_a
        end

        # @param identity [String] a unique process id, e.g. +hostname-pid+
        # @param info [Hash] the process details shown in the Web UI
        # @return [void]
        def register(identity, info)
          put(identity, info)
        end

        # @param identity [String]
        # @return [void]
        def unregister(identity)
          remove(identity)
        end
      end
    end
  end
end
