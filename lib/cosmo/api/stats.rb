# frozen_string_literal: true

require "cosmo/api/stats/totals"
require "cosmo/api/stats/busy"
require "cosmo/api/stats/processes"
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

      # @return [Integer] jobs running right now across all workers
      def busy
        Busy.instance.size
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
        busy = Busy.instance.by_stream
        Stream.jobs.map { queue(_1, busy) }
      end

      # @param stream [Stream] a job stream
      # @param busy [Hash{String => Integer}] running jobs per stream, as {Busy#by_stream} counts them
      # @return [Hash] the stream's +:name+, waiting messages as +:size+, running jobs as +:busy+, redeliveries as
      #   +:retries+, and whether it is +:paused+
      def queue(stream, busy = Busy.instance.by_stream)
        { name: stream.name, size: stream.size, busy: busy.fetch(stream.name, 0), retries: stream.retries,
          paused: stream.paused? }
      end
    end
  end
end
