# frozen_string_literal: true

module Cosmo
  module Job
    # Per-call job options, returned by {ClassMethods#set}: the enqueue methods merge them over the class options.
    #
    #   ReportJob.set(stream: :critical, retry: 0).perform_async(42)
    class Setter
      # Options carried by the job's message. The rest (+limit+, +retry_in+) are read from the class by the worker.
      OPTIONS = %i[stream retry dead subject].freeze

      # @param job_class [Class] the job class including {Job}
      # @param options [Hash] a subset of {OPTIONS}
      # @raise [ArgumentError] when an option is not one of {OPTIONS}
      def initialize(job_class, options)
        unknown = options.keys - OPTIONS
        if unknown.any?
          hint = " (use stream: instead of queue:)" if unknown.include?(:queue)
          raise ArgumentError, "unknown job options #{unknown.join(", ")}, expected #{OPTIONS.join(", ")}#{hint}"
        end

        @job_class = job_class
        @options = options
      end

      # @param args [Array] arguments passed to the job's +perform+
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      def perform_async(*args)
        @job_class.perform(*args, **@options)
      end

      # @param list [Array<Array>] each job's arguments
      # @return [Array<String, nil>] each job's jid, nil for one a client middleware stopped
      def perform_bulk(list)
        @job_class.perform_bulk(list, **@options)
      end

      # @param timestamp [Time, Integer] when the job runs
      # @param args [Array] arguments passed to the job's +perform+
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      def perform_at(timestamp, *args)
        @job_class.perform(*args, **@options, at: timestamp)
      end

      # @param interval [Numeric] seconds from now until the job runs
      # @param args [Array] arguments passed to the job's +perform+
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      def perform_in(interval, *args)
        @job_class.perform(*args, **@options, in: interval)
      end
    end
  end
end
