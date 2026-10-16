# frozen_string_literal: true

module Cosmo
  module Middleware
    # Lists the job on the Web UI's Busy page while it runs.
    class Busy
      # @param _job [Cosmo::Job, nil] nil when this worker can't load the job's class
      # @param _data [Hash]
      # @param message [NATS::Msg]
      # @yieldreturn [Object] the job's result
      # @return [Object] the block's result
      def call(_job, _data, message, &)
        API::Stats::Busy.instance.with(message, &)
      end
    end
  end
end
