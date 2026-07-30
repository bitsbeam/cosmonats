# frozen_string_literal: true

module Cosmo
  module ActiveJobAdapter
    # Cosmo::Job that deserializes and executes an ActiveJob payload
    class Executor
      include Cosmo::Job

      options stream: :default

      # Resolves +retry_in+ from the underlying ActiveJob class (declared via +cosmo_options+),
      # since the processor only ever sees +Executor+ as the worker class for ActiveJob-dispatched jobs.
      def self.retry_in(data)
        job_class = Utils::String.safe_constantize(data.dig(:args, 0, :job_class))
        return super unless job_class.respond_to?(:get_cosmo_options)

        job_class.get_cosmo_options[:retry_in] || super
      end

      def perform(job_data)
        ::ActiveJob::Base.execute(Utils::Hash.stringify_keys(job_data))
      end
    end
  end
end
