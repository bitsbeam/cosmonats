# frozen_string_literal: true

module Cosmo
  module ActiveJobAdapter
    # Adds +cosmo_options+ to ActiveJob classes.
    #
    #   class MyJob < ApplicationJob
    #     cosmo_options retry: 5, dead: false
    #
    #     def perform(user_id)
    #       # ...
    #     end
    #   end
    #
    # Options mirror those accepted by +Cosmo::Job+:
    #   retry:  [Integer]  Number of retries before giving up (default: 3)
    #   dead:   [Boolean]  Move to DLQ when retries exhausted? (default: true)
    #   stream: [Symbol]   Override the NATS stream (default: derived from queue_name)
    module Options
      VALID_OPTIONS = %i[retry dead stream].freeze

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Set Cosmo-specific options for this job class.
        # Merges with any options inherited from a superclass.
        # Raises +ArgumentError+ for unknown keys.
        def cosmo_options(**opts)
          unknown = opts.keys - Cosmo::ActiveJobAdapter::Options::VALID_OPTIONS
          raise ::ArgumentError, "Unknown cosmo_options key(s): #{unknown.join(", ")}" if unknown.any?

          @cosmo_options = get_cosmo_options.merge(opts)
        end

        # Returns the resolved options, walking up the inheritance chain.
        def get_cosmo_options # rubocop:disable Naming/AccessorMethodName
          if @cosmo_options
            @cosmo_options.dup
          elsif superclass.respond_to?(:get_cosmo_options)
            superclass.get_cosmo_options
          else
            {}
          end
        end
      end
    end
  end
end
