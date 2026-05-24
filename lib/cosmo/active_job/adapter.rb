# frozen_string_literal: true

module Cosmo
  module ActiveJobAdapter
    # ActiveJob queue adapter that enqueues jobs via NATS JetStream.
    #
    # Usage:
    #   config.active_job.queue_adapter = :cosmonats
    #   # or explicitly:
    #   config.active_job.queue_adapter = Cosmo::ActiveJobAdapter::Adapter.new
    #
    # The ActiveJob queue name maps directly to the Cosmo stream name.
    class Adapter
      # Enqueue a job to be run as soon as possible.
      # @param job [ActiveJob::Base]
      def enqueue(job)
        publish(job, nil)
      end

      # Enqueue a job to be run at (or after) a given time.
      # @param job [ActiveJob::Base]
      # @param timestamp [Numeric] Unix timestamp (seconds, float)
      def enqueue_at(job, timestamp)
        publish(job, timestamp)
      end

      private

      def publish(job, timestamp)
        cosmo_opts = job_cosmo_options(job)
        stream     = cosmo_opts.delete(:stream) || job.queue_name.to_sym
        options    = { stream: stream }.merge(cosmo_opts)
        options[:at] = timestamp if timestamp

        data = Job::Data.new(Executor.name, [job.serialize], options)
        Publisher.publish_job(data)
      end

      # Returns Cosmo-specific options declared on the job class via
      # +cosmo_options+, falling back to an empty hash.
      def job_cosmo_options(job)
        job.class.respond_to?(:get_cosmo_options) ? job.class.get_cosmo_options : {}
      end
    end
  end
end
