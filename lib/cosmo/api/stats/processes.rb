# frozen_string_literal: true

module Cosmo
  module API
    module Stats
      # Live worker processes, one entry per process, refreshed by Cosmo::Heartbeat.
      class Processes < Registry
        TTL = 60
        BUCKET = "cosmo_processes"

        # Sorted by host and pid before paging: every heartbeat rewrites an entry, so the bucket's own
        # order shifts constantly and would move processes between pages.
        #
        # @param page [Integer, nil]
        # @param limit [Integer]
        # @return [Array<Hash>]
        def list(page: nil, limit: LIMIT)
          offset = ([page.to_i, 1].max - 1) * limit
          all.sort_by { [_1[:hostname].to_s, _1[:pid].to_i] }.slice(offset, limit).to_a
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
