# frozen_string_literal: true

require "cosmo/api/counter"
require "cosmo/api/busy"

module Cosmo
  module API
    module Stats
      module_function

      def summary
        { processed:, failed:, busy:, enqueued:, retries:, scheduled:, dead: }
      end

      def processed
        Counter.instance.get(:processed)
      end

      def failed
        Counter.instance.get(:failed)
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
        Stream.new("scheduled").size
      end

      def dead
        Stream.new("dead").size
      end
    end
  end
end
