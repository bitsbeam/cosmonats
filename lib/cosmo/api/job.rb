# frozen_string_literal: true

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

      def error?
        !error_class.to_s.empty? || !error_message.to_s.empty?
      end

      def timestamp
        headers&.dig("Nats-Time-Stamp")
      end
    end
  end
end
