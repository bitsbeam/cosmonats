# frozen_string_literal: true

require "cosmo/job/data"
require "cosmo/job/limit"
require "cosmo/job/processor"

module Cosmo
  module Job
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # @option config [Symbol] :stream NATS stream to publish to (default: :default)
      # @option config [Integer, Boolean] :retry max delivery attempts before giving up (default: 3).
      #   +false+ is treated as 0 (no retries).
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
      def options(**config)
        if config[:limit] && config.dig(:limit, :concurrency) && !config.dig(:limit, :duration).to_i.positive?
          raise ArgumentError, "limit: duration is required when concurrency is set"
        end

        raise ArgumentError, "retry_in must be callable, e.g. ->(count, exception) { ... }" if config[:retry_in] && !config[:retry_in].respond_to?(:call)

        default_options.merge!(config)
      end
      alias cosmo_options options

      def limits_concurrency?
        !!concurrency_options
      end

      # Returns the +retry_in+ Proc/lambda (taking +(count, exception)+) configured for this job class, or
      # +nil+ when unset. Overridable by wrapper job classes (e.g. the ActiveJob executor) that need to
      # resolve it from something other than +self+.
      def retry_in(_data = nil)
        default_options[:retry_in]
      end

      # Returns a normalized concurrency config hash, or +nil+ when not configured.
      # Always contains +:limit+, +:key+, +:duration+, and +:retry_in+.
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
      def concurrency_key(args)
        config = concurrency_options
        return unless config

        base = Utils::String.underscore(name)
        suffix = config[:key]&.call(*args)
        suffix ? "#{base}/#{suffix}" : base
      end

      def perform(*args, async: true, **options)
        data = Data.new(name, args, default_options.merge(options))
        unless async
          payload = Utils::Json.parse(data.to_args[1])
          raise ArgumentError, "Cannot parse payload" unless payload

          new.perform(*payload[:args])
          return
        end

        Publisher.publish_job(data)
      end

      def perform_async(*args)
        perform(*args)
      end

      def perform_at(timestamp, *args)
        perform(*args, at: timestamp)
      end

      def perform_in(interval, *args)
        perform(*args, in: interval)
      end

      def perform_sync(*args)
        perform(*args, async: false)
      end

      def default_options
        @default_options ||= (superclass.respond_to?(:default_options) ? superclass.default_options : Data::DEFAULTS).dup
      end

      private

      def client
        @client ||= Client.instance
      end
    end

    attr_accessor :jid, :enqueued_at, :attempt, :scheduled_by

    def perform(...)
      raise NotImplementedError, "#{self.class}#perform must be implemented"
    end

    def logger
      Logger.instance
    end
  end
end
