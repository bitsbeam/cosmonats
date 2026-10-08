# frozen_string_literal: true

require "timeout"

module Cosmo
  module Middleware
    # Enforces a job class's +limit:+ option: a concurrency slot per key, requeueing the job while every slot is
    # taken, and the +duration+ timeout. Jobs without +limit:+ pass straight through. It runs first in the chain,
    # so a requeued job never reaches the stats or user middleware.
    class Limit
      # @param job [Cosmo::Job]
      # @param data [Hash]
      # @param _message [NATS::Msg]
      # @raise [Job::Requeue] while every concurrency slot is taken
      def call(job, data, _message, &)
        limit = job.class.default_options[:limit]
        return yield unless limit

        slot = acquire(job.class, data)
        timeout(limit[:duration], &)
      ensure
        Job::Limit.instance.release(slot) if slot
      end

      private

      def acquire(job_class, data)
        options = job_class.concurrency_options
        return unless options

        key = job_class.concurrency_key(data[:args])
        slot = Job::Limit.instance.acquire(key, jid: data[:jid], limit: options[:limit], duration: options[:duration])
        raise Job::Requeue, options[:retry_in] unless slot

        slot
      rescue NATS::Error => e
        Logger.error e
        raise Job::Requeue
      end

      def timeout(duration, &)
        return yield unless duration

        seconds = duration.to_i
        Timeout.timeout(seconds, Timeout::Error, "execution expired after the #{seconds}s duration limit", &)
      end
    end
  end
end
