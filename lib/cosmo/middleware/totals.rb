# frozen_string_literal: true

module Cosmo
  module Middleware
    # Counts every execution as processed or failed, so a job retried twice and then succeeding adds two failures
    # and one processed. A counter that cannot be written is logged rather than raised, so stats never fail a job.
    class Totals
      # @param _job [Cosmo::Job]
      # @param _data [Hash]
      # @param _message [NATS::Msg]
      def call(_job, _data, _message)
        result = yield
        increment(:processed)
        result
      rescue Exception # rubocop:disable Lint/RescueException
        increment(:failed)
        raise
      end

      private

      def increment(key)
        API::Stats::Totals.instance.increment(key)
      rescue StandardError => e
        Logger.debug "Totals #{key} counter error: #{e.class} #{e.message}"
      end
    end
  end
end
