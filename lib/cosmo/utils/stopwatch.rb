# frozen_string_literal: true

module Cosmo
  module Utils
    class Stopwatch
      def initialize
        reset
      end

      # @return [Float] A number of elapsed milliseconds
      def elapsed_millis
        (clock_time - @started_at).round(2)
      end

      # @return [Float] A number of elapsed seconds
      def elapsed_seconds
        (elapsed_millis / 1_000).round(2)
      end

      def reset
        @started_at = clock_time
      end

      private

      # @return [Float]
      def clock_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      end
    end
  end
end
