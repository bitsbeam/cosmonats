# frozen_string_literal: true

module Cosmo
  module ActiveJobAdapter
    # Cosmo::Job that deserializes and executes an ActiveJob payload
    class Executor
      include Cosmo::Job

      options stream: :default

      def perform(job_data)
        ::ActiveJob::Base.execute(Utils::Hash.stringify_keys(job_data))
      end
    end
  end
end
