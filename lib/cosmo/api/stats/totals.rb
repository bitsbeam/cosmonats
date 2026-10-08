# frozen_string_literal: true

module Cosmo
  module API
    module Stats
      # Processed and failed job totals across all workers, in the +_cosmototals+ counters. They never expire.
      class Totals < Counter
        STREAM_NAME = "_cosmototals"
        DESCRIPTION = "Cosmo statistics"

        def self.instance
          @instance ||= new("jobs")
        end

        # @return [Integer]
        def processed
          get(:processed)
        end

        # @return [Integer]
        def failed
          get(:failed)
        end
      end
    end
  end
end
