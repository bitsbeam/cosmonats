# frozen_string_literal: true

module Cosmo
  module Utils
    class Signal
      # Traps the given signals, see {#initialize}.
      #
      # @return [Signal]
      def self.trap(...)
        new(...)
      end

      # @param signals [Array<Symbol, String>] signals to trap
      def initialize(*signals)
        @queue = Queue.new
        signals.each { |s| ::Signal.trap(s) { push(s) } }
      end

      # Blocks until a trapped signal arrives.
      #
      # @return [Symbol, String] the signal
      def wait
        @queue.pop # Wait indefinitely for a signal
      end

      # @param signal [Symbol, String]
      # @return [void]
      def push(signal)
        @queue.push(signal)
      end
    end
  end
end
