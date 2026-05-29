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
      # @option config [Symbol]  :stream  NATS stream to publish to (default: :default)
      # @option config [Integer] :retry   max delivery attempts before giving up (default: 3)
      # @option config [Boolean] :dead    move to dead-letter stream after retries exhausted (default: true)
      # @option config [Hash]    :limit   execution limits:
      #
      #   limit: { duration: 30 }
      #   limit: { duration: 30, concurrency: 3 }
      #   limit: { duration: 30, concurrency: { to: 3, key: ->(id) { id } } }
      #
      # @option config [Integer] :"limit[:duration]"    hard execution timeout in seconds. The job thread is
      #   killed after this many seconds and counts as a failed attempt (retried with exponential backoff,
      #   moved to DLQ after retries exhausted).
      # @option config [Integer, Hash] :"limit[:concurrency]"  caps how many instances run at once across all
      #   workers. Jobs that cannot acquire a slot are NAK'd with a delay equal to +duration+ so they are not
      #   re-delivered until the slot is guaranteed free. Requires +duration+.
      #   Pass an Integer for a class-wide cap, or <tt>{ to: N, key: ->(args) {} }</tt> to scope per key.
      def options(**config)
        if config[:limit] && config.dig(:limit, :concurrency) && !config.dig(:limit, :duration).to_i.positive?
          raise ArgumentError, "limit: duration is required when concurrency is set"
        end

        default_options.merge!(config)
      end
      alias cosmo_options options

      def limits_concurrency?
        !!concurrency_options
      end

      # Returns a normalized concurrency config hash, or +nil+ when not configured.
      # Always contains +:limit+, +:key+, and +:duration+.
      def concurrency_options
        value = default_options.dig(:limit, :concurrency)
        duration = default_options.dig(:limit, :duration).to_i
        return unless value

        case value
        when Integer then { limit: value, key: nil, duration: duration }
        when Hash    then { limit: value.fetch(:to), key: value[:key], duration: duration }
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

    attr_accessor :jid

    def perform(...)
      raise NotImplementedError, "#{self.class}#perform must be implemented"
    end

    def logger
      Logger.instance
    end
  end
end
