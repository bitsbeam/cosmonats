# frozen_string_literal: true

module Cosmo
  module Job
    # Which job streams a worker subscribes to: every configured stream, or the subset named by
    # +--streams+/+--stream+, falling back to the +COSMO_JOBS_STREAMS+ environment variable.
    #
    # The scheduled stream is a service stream. Naming it selects nothing, it runs unless the worker
    # was started with +--no-scheduler+.
    class StreamFilter
      SCHEDULED = :scheduled
      ENV_NAME = "COSMO_JOBS_STREAMS"

      # @param names [Array<String>, nil] stream names from the command line
      # @return [StreamFilter]
      def self.from(names)
        new(names || ENV[ENV_NAME]&.split(","))
      end

      # @param names [Array<String>, nil]
      def initialize(names)
        @names = Array(names).map(&:strip).reject(&:empty?)
      end

      # @return [Boolean] whether every configured stream is selected
      def all?
        @names.empty?
      end

      # @param stream_name [String, Symbol]
      # @return [Boolean] whether the stream is selected
      def include?(stream_name)
        all? || @names.include?(stream_name.to_s)
      end

      # @return [StreamFilter] self, so it can be chained onto {.from}
      # @raise [UnknownJobStreamError] when a name is not configured
      def validate!
        return self if all?

        unknown = @names - configured - [SCHEDULED.to_s]
        raise UnknownJobStreamError.new(unknown, configured) if unknown.any?

        self
      end

      private

      def configured
        @configured ||= Config.dig(:consumers, :jobs)&.keys.to_a.map(&:to_s) - [SCHEDULED.to_s]
      end
    end
  end
end
