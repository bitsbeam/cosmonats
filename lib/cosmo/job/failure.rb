# frozen_string_literal: true

module Cosmo
  module Job
    # Describes why a job died, as NATS headers carried alongside the payload in the
    # dead letter queue. The worker that raised is long gone by the time the dead jobs
    # page is rendered, so the cause has to travel with the message itself.
    class Failure
      HEADER_LIMIT = 1024
      BACKTRACE_LINES = 10

      # @param exception [Exception]
      # @return [Hash{String => String}] headers describing the failure
      def self.headers(exception)
        new(exception).headers
      end

      # @param exception [Exception]
      def initialize(exception)
        @exception = exception
      end

      # @return [Hash{String => String}]
      def headers
        headers = { "X-Error-Class" => name, "X-Error-Message" => message }
        headers["X-Error-Backtrace"] = backtrace unless backtrace.empty?
        headers
      end

      private

      def name
        @exception.class.name.to_s
      end

      def message
        value = single_line(@exception.message)
        value.empty? ? name : value
      end

      def backtrace
        @backtrace ||= single_line(Array(@exception.backtrace).first(BACKTRACE_LINES).join(" | "))
      end

      # NATS header values are a single line, so whitespace collapses and the value is capped.
      def single_line(value)
        value.to_s.gsub(/\s+/, " ").strip[0, HEADER_LIMIT].to_s
      end
    end
  end
end
