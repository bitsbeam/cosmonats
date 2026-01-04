# frozen_string_literal: true

module Cosmo
  module Utils
    class Signal
      def self.trap(...)
        new(...)
      end

      def initialize(*signals)
        @queue = SizedQueue.new(1)
        signals.each { |s| ::Signal.trap(s) { @queue.push(s) } }
      end

      def wait
        @queue.pop # Wait indefinitely for a signal
      end
    end
  end
end
