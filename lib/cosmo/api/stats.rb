# frozen_string_literal: true

require "cosmo/api/stats/totals"
require "cosmo/api/stats/busy"
require "cosmo/api/stats/processes"

module Cosmo
  module API
    module Stats
      module_function

      def summary
        { processed:, failed:, busy:, enqueued:, retries:, scheduled:, dead: }
      end

      def processed
        Totals.instance.processed
      end

      def failed
        Totals.instance.failed
      end

      def busy
        Busy.instance.size
      end

      def enqueued
        Stream.jobs.sum(&:size)
      end

      def retries
        Stream.jobs.sum(&:retries)
      end

      def scheduled
        Config.scheduled.enabled ? Stream.new("scheduled").size : 0
      end

      def dead
        Config.dead.enabled ? Stream.new("dead").size : 0
      end
    end
  end
end
