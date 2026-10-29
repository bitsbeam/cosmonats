# frozen_string_literal: true

require "cosmo/job/data"
require "cosmo/job/enqueuer"
require "cosmo/job/setter"
require "cosmo/job/requeue"
require "cosmo/job/failure"
require "cosmo/job/stream_filter"
require "cosmo/job/limit"
require "cosmo/job/processor"

module Cosmo
  module Job
    # @param base [Class] the job class including Job
    # @return [void]
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # @option config [Symbol] :stream NATS stream to publish to (default: :default)
      # @option config [Integer, Boolean] :retry max delivery attempts before giving up (default: +max_retries+
      #   from cosmo.yml, or 3 if unset). +false+ is treated as 0 (no retries). Should stay comfortably under
      #   the assigned stream's consumer +max_deliver+ (a coarse, shared safety ceiling, not a per-job budget) --
      #   a job whose +retry:+ exceeds it is capped and dead-lettered a delivery early, with a warning logged.
      # @option config [Boolean] :dead move to dead-letter stream after retries exhausted (default: true)
      # @option config [Hash] :limit execution limits:
      #
      #   limit: { duration: 30 }
      #   limit: { duration: 30, concurrency: 3 }
      #   limit: { duration: 30, concurrency: { to: 3, key: ->(id) { id } } }
      #   limit: { duration: 30, concurrency: 3, retry_in: 5 }
      #
      # @option config [Integer] :"limit[:duration]" hard execution timeout in seconds. The job thread is
      #   killed after this many seconds and counts as a failed attempt (retried with exponential backoff,
      #   moved to DLQ after retries exhausted).
      # @option config [Integer, Hash] :"limit[:concurrency]" caps how many instances run at once across all
      #   workers. Jobs that cannot acquire a slot are NAK'd (see +retry_in+) so they are not re-delivered until
      #   the slot is likely free. Requires +duration+.
      #   Pass an Integer for a class-wide cap, or <tt>{ to: N, key: ->(args) {} }</tt> to scope per key.
      # @option config [Integer] :"limit[:retry_in]" seconds to wait before NATS redelivers a job that was
      #   NAK'd for lack of a concurrency slot (default: half of +duration+). Counts against the same delivery
      #   counter as any other retry -- a job stuck behind the concurrency limit for enough consecutive
      #   attempts is dropped/DLQ'd exactly like one that keeps failing outright.
      # @option config [Proc] :retry_in <tt>->(count, exception) { }</tt> returns a number of seconds to
      #   wait before redelivering a *failed* job. +count+ is a 1-based delivery attempt that just failed.
      #   Falls back to the default backoff (<tt>attempt**4 + 15</tt> seconds) if not set or the proc returns
      #   a non-numeric/non-positive value, or if it raises.
      #
      #   Caveat when combined with +limit[:concurrency]+: when there's no free slot to run in, the message is
      #   put back on the stream using the +limit[:retry_in]+ delay described above, and that counts as an
      #   attempt too -- the same +count+ goes up whether the job was turned away for lack of a free slot (via
      #   +limit[:retry_in]+) or actually ran and failed. So a job that gets turned away twice for lack of a
      #   slot, then finally runs and fails, calls this handler with +count == 3+, not 1. Don't read +count+ as
      #   "how many times perform has actually run and failed" when concurrency limits are in play.
      # @return [Hash{Symbol => Object}] the class's merged options
      # @raise [ArgumentError] when +limit[:concurrency]+ lacks a +duration+ or +retry_in+ is not callable
      def options(**config)
        if config[:limit] && config.dig(:limit, :concurrency) && !config.dig(:limit, :duration).to_i.positive?
          raise ArgumentError, "limit: duration is required when concurrency is set"
        end

        raise ArgumentError, "retry_in must be callable, e.g. ->(count, exception) { ... }" if config[:retry_in] && !config[:retry_in].respond_to?(:call)

        default_options.merge!(config)
      end
      alias cosmo_options options

      # @return [Boolean] whether +limit[:concurrency]+ is configured
      def limits_concurrency?
        !!concurrency_options
      end

      # Returns the +retry_in+ Proc/lambda (taking +(count, exception)+) configured for this job class, or
      # +nil+ when unset. Overridable by wrapper job classes (e.g. the ActiveJob executor) that need to
      # resolve it from something other than +self+.
      #
      # @param _data [Hash, nil] the job payload, unused here
      # @return [Proc, nil]
      def retry_in(_data = nil)
        default_options[:retry_in]
      end

      # Returns a normalized concurrency config hash, or +nil+ when not configured.
      # Always contains +:limit+, +:key+, +:duration+, and +:retry_in+.
      #
      # @return [Hash{Symbol => Object}, nil]
      def concurrency_options
        value = default_options.dig(:limit, :concurrency)
        return unless value

        duration = default_options.dig(:limit, :duration).to_i
        retry_in = default_options.dig(:limit, :retry_in)&.to_i || (duration / 2)

        case value
        when Integer then { limit: value, key: nil, duration: duration, retry_in: retry_in }
        when Hash    then { limit: value.fetch(:to), key: value[:key], duration: duration, retry_in: retry_in }
        end
      end

      # Derive the fully-scoped concurrency key for a given args array.
      #
      # @param args [Array] the job's arguments
      # @return [String, nil] nil when concurrency is not limited
      def concurrency_key(args)
        config = concurrency_options
        return unless config

        base = Utils::String.underscore(name)
        suffix = config[:key]&.call(*args)
        suffix ? "#{base}/#{suffix}" : base
      end

      # Enqueues the job, or runs it inline when +async+ is false.
      #
      # @param args [Array] arguments passed to the job's +perform+
      # @param async [Boolean] false runs the job in the current thread, without NATS
      # @param options [Hash] job options merged over {#default_options}, e.g. +at:+ or +in:+
      # @return [String, nil] the job's jid, or nil when run inline or a client middleware stopped the publish
      def perform(*args, async: true, **options)
        options = default_options.merge(options)
        return Enqueuer.enqueue(name, args, options, batch: Batch.current) if async

        payload = Utils::Json.parse(Data.new(name, args, options).to_json)
        raise ArgumentError, "Cannot parse payload" unless payload

        new.perform(*payload[:args])
        nil
      end

      # Options for a single enqueue, merged over the class options.
      #
      #   ReportJob.set(stream: :critical, retry: 0).perform_async(42)
      #
      # @param options [Hash] +stream+, +retry+, +dead+ or +subject+, see {#options}
      # @return [Setter]
      # @raise [ArgumentError] for any other option
      def set(**options)
        Setter.new(self, options)
      end

      # @param args [Array] arguments passed to the job's +perform+
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      def perform_async(*args)
        perform(*args)
      end

      # Enqueues one job per argument list, publishing a thousand at a time without waiting on each ack.
      #
      #   ReportJob.perform_bulk([[1], [2], [3]])
      #
      # @param list [Array<Array>] each job's arguments
      # @param options [Hash] job options for every job, merged over {#default_options}, e.g. +in:+
      # @return [Array<String, nil>] each job's jid, nil for one a client middleware stopped
      # @raise [BulkEnqueueError] when the stream refused some jobs; its +jids+ tell which were enqueued
      def perform_bulk(list, **options)
        Enqueuer.enqueue_many(name, list, default_options.merge(options), batch: Batch.current)
      end

      # @param timestamp [Time, Integer] when the job runs
      # @param args [Array] arguments passed to the job's +perform+
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      def perform_at(timestamp, *args)
        perform(*args, at: timestamp)
      end

      # @param interval [Numeric] seconds from now until the job runs
      # @param args [Array] arguments passed to the job's +perform+
      # @return [String, nil] the job's jid, or nil when a client middleware stopped the publish
      def perform_in(interval, *args)
        perform(*args, in: interval)
      end

      # Runs the job inline, without NATS.
      #
      # @param args [Array] arguments passed to the job's +perform+
      # @return [nil]
      def perform_sync(*args)
        perform(*args, async: false)
      end

      # Options inherited from the superclass job, or the built-in defaults.
      #
      # @return [Hash{Symbol => Object}]
      def default_options
        @default_options ||= (superclass.respond_to?(:default_options) ? superclass.default_options : Data::DEFAULTS.merge(retry: Data.default_retry)).dup
      end

      private

      def client
        @client ||= Client.instance
      end
    end

    attr_accessor :jid, :batch_id, :enqueued_at, :attempt, :scheduled_by

    # Runs the job with the arguments it was enqueued with.
    #
    # @return [Object]
    # @raise [NotImplementedError] unless the job class overrides it
    def perform(...)
      raise NotImplementedError, "#{self.class}#perform must be implemented"
    end

    # @return [::Logger]
    def logger
      Logger.instance
    end
  end
end
