# frozen_string_literal: true

module Cosmo
  module API
    module Stats
      # The jobs running right now, one entry per job, refreshed by the worker running it through Cosmo::Heartbeat.
      #
      # An entry's key is +<stream>.<worker>.<jid>+, so how many jobs run, in all or on one stream, is a count the
      # server answers without reading an entry. A worker that dies leaves entries that expire with the bucket's TTL,
      # so the counts never drift.
      class Jobs < Registry
        TTL = 60
        BUCKET = "_cosmojobs"
        LONGEST_TTL = 5

        def initialize
          super
          @mutex = Mutex.new
          @reported = {}
        end

        # Writes the jobs +identity+ is running and removes the ones it ran at its last report and has finished.
        #
        # @param identity [String] the worker, e.g. +hostname-pid+
        # @param jobs [Array<Hash>] each with +:jid+ and +:stream+
        # @return [void]
        def report(identity, jobs)
          entries = jobs.to_h { |job| [key_for(identity, job), job.merge(worker: identity)] }
          put_many(entries) unless entries.empty?
          (@reported.fetch(identity, []) - entries.keys).each { remove(_1) }
          @reported[identity] = entries.keys
        end

        # Removes every job +identity+ reported.
        #
        # @param identity [String]
        # @return [void]
        def clear(identity)
          @reported.delete(identity)
          @kv.erase("*.#{Registry.token(identity)}.*")
        end

        # @param stream [String, nil] only the jobs on this stream
        # @return [Integer] the jobs running, counted by the server
        def count(stream = nil)
          @kv.direct_count(stream && "#{Registry.token(stream)}.>")
        end

        # Some running jobs, as many as +limit+, with no say in which: the first ones NATS holds. Costs one small read
        # however many jobs run, so it suits a glance at what is running, not a listing.
        #
        # @param limit [Integer]
        # @return [Array<Hash>]
        def sample(limit)
          @kv.direct_entries(nil, limit:).filter_map { Utils::Json.parse(_1.last) }
        end

        # One page of the running jobs, longest running first. Ordering them takes reading every job, so that read
        # happens at most once per LONGEST_TTL and is shared by every caller; concurrent callers wait for it.
        #
        # @param page [Integer, nil]
        # @param limit [Integer]
        # @return [Array<Hash>]
        def longest(page: nil, limit: LIMIT)
          @mutex.synchronize do
            now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            unless @longest && now - @longest_at < LONGEST_TTL
              @longest = all.sort_by { _1[:started_at].to_i }.freeze
              @longest_at = now
            end
            @longest.slice(([page.to_i, 1].max - 1) * limit, limit).to_a
          end
        end

        private

        def key_for(identity, job)
          [job[:stream], identity, job[:jid]].map { Registry.token(_1) }.join(".")
        end
      end
    end
  end
end
