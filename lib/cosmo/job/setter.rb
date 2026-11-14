# frozen_string_literal: true

module Cosmo
  module Job
    # Per-call job options, returned by {ClassMethods#set}: the enqueue methods merge them over the class options.
    #
    #   ReportJob.set(stream: :critical, retry: 0).perform_async(42)
    #
    # It is also where a job's id is fixed instead of generated: +jid:+ for one job, +jids:+ for {#perform_bulk}.
    # JetStream stores a +Nats-Msg-Id+ it has seen within the stream's +duplicate_window+ once, so enqueueing the same
    # jid again in that time is a no-op.
    #
    #   ReportJob.set(jid: "report-42").perform_async(42)
    #   ReportJob.set(jids: ->(args) { "report-#{args.first}" }).perform_bulk([[1], [2]])
    class Setter
      # Options carried by the job's message. The rest (+limit+, +retry_in+) are read from the class by the worker.
      OPTIONS = %i[stream retry dead subject lane jid jids].freeze

      # @param job_class [Class] the job class including {Job}
      # @param options [Hash] a subset of {OPTIONS}
      # @raise [ArgumentError] when an option is not one of {OPTIONS}, or both +jid+ and +jids+ are given
      def initialize(job_class, options)
        unknown = options.keys - OPTIONS
        if unknown.any?
          hint = " (use stream: instead of queue:)" if unknown.include?(:queue)
          raise ArgumentError, "unknown job options #{unknown.join(", ")}, expected #{OPTIONS.join(", ")}#{hint}"
        end
        raise ArgumentError, "use jid: for one job or jids: for perform_bulk, not both" if options.key?(:jid) && options.key?(:jids)

        @job_class = job_class
        @jid = options[:jid]
        @jids = options[:jids]
        @options = options.except(:jid, :jids)
      end

      # @param args [Array] arguments passed to the job's +perform+
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      # @raise [ArgumentError] when +jids+ was set, it is for {#perform_bulk}
      def perform_async(*args)
        @job_class.perform(*args, **job_options)
      end

      # @param list [Array<Array>] each job's arguments
      # @return [Array<String, nil>] each job's jid, nil for one a client middleware stopped
      # @raise [ArgumentError] when +jid+ was set, +jids+ is for a list, or when +jids+ is not one jid per job
      def perform_bulk(list)
        raise ArgumentError, "jid: is for one job, use jids: with perform_bulk" if @jid

        @job_class.perform_bulk(list, jids: @jids, **@options)
      end

      # @param timestamp [Time, Integer] when the job runs
      # @param args [Array] arguments passed to the job's +perform+
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      # @raise [ArgumentError] when +jids+ was set, it is for {#perform_bulk}
      def perform_at(timestamp, *args)
        @job_class.perform(*args, **job_options, at: timestamp)
      end

      # @param interval [Numeric] seconds from now until the job runs
      # @param args [Array] arguments passed to the job's +perform+
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      # @raise [ArgumentError] when +jids+ was set, it is for {#perform_bulk}
      def perform_in(interval, *args)
        @job_class.perform(*args, **job_options, in: interval)
      end

      private

      def job_options
        raise ArgumentError, "jids: is for perform_bulk, use jid: for one job" if @jids

        @jid ? @options.merge(jid: @jid) : @options
      end
    end
  end
end
