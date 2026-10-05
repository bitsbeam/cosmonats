# frozen_string_literal: true

require "time"

module Cosmo
  module API
    class Job
      attr_reader :message, :stream

      def initialize(stream, message)
        @stream = stream
        @message = message
      end

      def data
        @data ||= Utils::Json.parse(@message.data)
      end

      def seq
        @message.seq
      end

      def headers
        @message.headers
      end

      def execute_at
        headers&.dig("X-Execute-At")&.to_i
      end

      def x_stream
        headers&.dig("X-Stream")
      end

      def x_subject
        headers&.dig("X-Subject")
      end

      def subject
        @message.subject
      end

      def error_class
        headers&.dig("X-Error-Class")
      end

      def error_message
        headers&.dig("X-Error-Message")
      end

      def error_backtrace
        headers&.dig("X-Error-Backtrace")
      end

      # @return [Array<String>] the backtrace frames, which travel as a single header line
      def error_backtrace_lines
        error_backtrace.to_s.split(::Cosmo::Job::Failure::BACKTRACE_SEPARATOR)
      end

      def error?
        !error_class.to_s.empty? || !error_message.to_s.empty?
      end

      def timestamp
        headers&.dig("Nats-Time-Stamp")
      end

      # @return [Time, nil] when the message was stored in its stream, parsed from +Nats-Time-Stamp+
      def stored_at
        Time.iso8601(timestamp) if timestamp
      rescue ::ArgumentError
        nil
      end
    end
  end
end
