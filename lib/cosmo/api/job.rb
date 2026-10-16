# frozen_string_literal: true

require "time"

module Cosmo
  module API
    class Job
      attr_reader :message, :stream

      # @param stream [String] the stream the message was read from
      # @param message [NATS::JetStream::API::RawStreamMsg]
      def initialize(stream, message)
        @stream = stream
        @message = message
      end

      # @return [Hash, nil] the parsed job payload
      def data
        @data ||= Utils::Json.parse(@message.data)
      end

      # @return [Integer, String] the message's stream sequence, a String when read by direct get
      def seq
        @message.seq
      end

      # @return [Hash{String => String}, nil]
      def headers
        @message.headers
      end

      # @return [Integer, nil] when a scheduled job is due, from +X-Execute-At+
      def execute_at
        headers&.dig("X-Execute-At")&.to_i
      end

      # @return [String, nil] the stream a scheduled or dead job belongs to, from +X-Stream+
      def x_stream
        headers&.dig("X-Stream")
      end

      # @return [String, nil] the subject a scheduled or dead job is dispatched to, from +X-Subject+
      def x_subject
        headers&.dig("X-Subject")
      end

      # @return [String]
      def subject
        @message.subject
      end

      # @return [String, nil] the last failure's exception class, from +X-Error-Class+
      def error_class
        headers&.dig("X-Error-Class")
      end

      # @return [String, nil] the last failure's message, from +X-Error-Message+
      def error_message
        headers&.dig("X-Error-Message")
      end

      # @return [String, nil] the last failure's backtrace as one line, from +X-Error-Backtrace+
      def error_backtrace
        headers&.dig("X-Error-Backtrace")
      end

      # @return [Array<String>] the backtrace frames, which travel as a single header line
      def error_backtrace_lines
        error_backtrace.to_s.split(::Cosmo::Job::Failure::BACKTRACE_SEPARATOR)
      end

      # @return [Boolean] whether the message carries a failure
      def error?
        !error_class.to_s.empty? || !error_message.to_s.empty?
      end

      # @return [String, nil] the +Nats-Time-Stamp+ header
      def timestamp
        headers&.dig(NATS::JetStream::Header::TIME_STAMP)
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
