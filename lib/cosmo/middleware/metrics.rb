# frozen_string_literal: true

module Cosmo
  module Middleware
    # Records every execution for the web UI's Metrics tab while +config.metrics+ is enabled: its run time when it
    # succeeds, a failure otherwise, and the wait from enqueue to the job's first delivery. ActiveJob jobs count under
    # their own class.
    class Metrics
      # @param job [Cosmo::Job]
      # @param data [Hash]
      # @param _message [NATS::Msg]
      def call(job, data, _message) # rubocop:disable Metrics/AbcSize
        return yield unless Config.metrics.enabled

        name = job_name(job, data)
        wait_ms = (Time.now - job.enqueued_at) * 1000 if job.attempt == 1 && job.enqueued_at
        started = clock
        result = yield
        API::Stats::Metrics.instance.record(name, exec_ms: clock - started, wait_ms:)
        result
      rescue Exception # rubocop:disable Lint/RescueException
        API::Stats::Metrics.instance.record(name, wait_ms:, failed: true) if name
        raise
      end

      private

      def job_name(job, data)
        return job.class.name unless defined?(ActiveJobAdapter::Executor) && job.is_a?(ActiveJobAdapter::Executor)

        data.dig(:args, 0, :job_class).to_s
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      end
    end
  end
end
