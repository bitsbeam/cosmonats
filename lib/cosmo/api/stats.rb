# frozen_string_literal: true

require "cosmo/api/stats/totals"
require "cosmo/api/stats/processes"
require "cosmo/api/stats/jobs"
require "cosmo/api/stats/metrics"

module Cosmo
  module API
    module Stats
      module_function

      # @return [Hash{Symbol => Integer}] the dashboard counts: +:processed+, +:failed+, +:busy+, +:enqueued+,
      #   +:retries+, +:scheduled+ and +:dead+
      def summary
        jobs = Stream.jobs
        { processed:, failed:, busy:, enqueued: enqueued(jobs), retries: retries(jobs), scheduled:, dead: }
      end

      # @return [Integer] jobs run successfully, ever
      def processed
        Totals.instance.processed
      end

      # @return [Integer] failed job attempts, ever
      def failed
        Totals.instance.failed
      end

      # @param limit [Integer]
      # @return [Array<Hash>] up to +limit+ of the jobs running right now, which ones is not defined, each with the
      #   +:worker+ running it; up to Heartbeat::INTERVAL old, and missing a job shorter than that
      def running(limit)
        Jobs.instance.sample(limit)
      end

      # @param page [Integer]
      # @param limit [Integer]
      # @param longest [Boolean] longest running first, which reads every running job (at most once per
      #   Jobs::LONGEST_TTL) instead of only the page
      # @return [Array<Hash>] the jobs running right now on a page, in stream, worker and job id order unless
      #   +longest+, each with the +:worker+ running it; see {.busy} for how many there are
      def running_page(page:, limit:, longest: false)
        longest ? Jobs.instance.longest(page:, limit:) : Jobs.instance.list(page:, limit:)
      end

      # @return [Integer] jobs running right now across all workers, counted by the server
      def busy
        Jobs.instance.count
      end

      # @param streams [Array<Stream>] the job streams
      # @return [Hash{String => Integer}] the number of jobs running per stream
      def busy_streams(streams = Stream.jobs)
        streams.to_h { [_1.name, Jobs.instance.count(_1.name)] }
      end

      # @param streams [Array<Stream>] the job streams
      # @return [Integer]
      def enqueued(streams = Stream.jobs)
        streams.sum(&:size)
      end

      # @param streams [Array<Stream>] the job streams
      # @return [Integer]
      def retries(streams = Stream.jobs)
        streams.sum(&:retries)
      end

      # @return [Integer] messages in the +scheduled+ stream, 0 while scheduling is off
      def scheduled
        Config.scheduled.enabled ? Stream.new("scheduled").size : 0
      end

      # @return [Integer] messages in the +dead+ stream, 0 while it is off
      def dead
        Config.dead.enabled ? Stream.new("dead").size : 0
      end

      # @return [Array<Hash>] a {.queue} row per job stream
      def queues
        streams = Stream.jobs
        busy = busy_streams(streams)
        streams.map { queue(_1, busy) }
      end

      # @param stream [Stream] a job stream
      # @param busy [Hash{String => Integer}] running jobs per stream, as {.busy_streams} counts them
      # @return [Hash] the stream's +:name+, waiting messages as +:size+, running jobs as +:busy+, redeliveries as
      #   +:retries+, and whether it is +:paused+
      def queue(stream, busy = busy_streams([stream]))
        { name: stream.name, size: stream.size, busy: busy.fetch(stream.name, 0), retries: stream.retries,
          paused: stream.paused? }
      end
    end
  end
end
