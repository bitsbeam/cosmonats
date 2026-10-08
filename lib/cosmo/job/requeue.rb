# frozen_string_literal: true

module Cosmo
  module Job
    # Raised by a middleware to put the job back on its stream for later: the processor naks it with +delay+ instead
    # of failing it. The redelivery still counts as a delivery attempt toward the job's +retry+ and +max_deliver+.
    # Raise it from a middleware that runs before the built-in stats middleware, or the attempt is counted as failed.
    #
    #   raise Cosmo::Job::Requeue.new(30) if maintenance?
    class Requeue < StandardError
      attr_reader :delay

      # @param delay [Numeric] seconds before the job is delivered again
      def initialize(delay = 0)
        @delay = delay
        super("requeued for #{delay}s")
      end
    end
  end
end
