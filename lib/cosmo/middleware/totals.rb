# frozen_string_literal: true

module Cosmo
  module Middleware
    # Counts every execution as processed or failed, so a job retried twice and then succeeding adds two failures
    # and one processed. A counter that cannot be written is logged rather than raised, so stats never fail a job.
    class Totals
      # @param _job [Cosmo::Job, nil] nil when this worker can't load the job's class
      # @param _data [Hash]
      # @param _message [NATS::Msg]
      # @yieldreturn [Object] the job's result
      # @return [Object] the block's result
      def call(_job, _data, _message)
        result = yield
        API::Stats::Totals.instance.increment(:processed)
        result
      rescue Exception # rubocop:disable Lint/RescueException
        API::Stats::Totals.instance.increment(:failed)
        raise
      end
    end
  end
end
