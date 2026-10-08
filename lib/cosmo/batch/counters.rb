# frozen_string_literal: true

require "cosmo/api/counter"

module Cosmo
  class Batch
    # Every batch's total, pending, and failed counters, in the +_cosmobatches+ stream. They are purged once the batch
    # finishes, and expire +config.batches.expiry+ after their last update otherwise, along with the batch's KV state.
    class Counters < API::Counter
      STREAM_NAME = "_cosmobatches"
      DESCRIPTION = "Cosmo batch progress"

      # @return [Hash]
      def self.stream_config
        super.merge(max_age: Config.to_ns(Utils::Duration.parse(Config.batches.expiry)))
      end
    end
  end
end
