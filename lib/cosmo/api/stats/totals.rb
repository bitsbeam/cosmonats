# frozen_string_literal: true

module Cosmo
  module API
    module Stats
      # Processed and failed job totals across all workers.
      class Totals < Counter
        def self.instance
          @instance ||= new("jobs")
        end

        # Counts the block's outcome: +true+ is processed, +false+ or a raise is failed.
        #
        # @return [void]
        def with
          result = yield
          increment(:processed) if result == true
          increment(:failed) if result == false
        rescue Exception # rubocop:disable Lint/RescueException
          increment(:failed)
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
