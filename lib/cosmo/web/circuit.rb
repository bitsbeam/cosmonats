# frozen_string_literal: true

module Cosmo
  class Web
    # Keeps the web UI from tying up server threads on an unreachable NATS: it is open, and requests answer at once
    # without touching NATS, while the client is disconnected or for OPEN_FOR seconds after a request failed on a
    # NATS timeout or connection error. The first request after that tries NATS again.
    class Circuit
      OPEN_FOR = 10
      ERRORS = [NATS::IO::Timeout, NATS::IO::ConnectError, NATS::IO::ConnectionClosedError,
                NATS::IO::StaleConnectionError].freeze

      def self.instance
        @instance ||= new
      end

      def initialize
        @lock = Mutex.new
        @tripped_at = nil
      end

      # @return [Boolean] whether requests should skip NATS
      def open?
        return true if tripped?
        return false if connected?

        trip!
        true
      end

      # Opens the circuit for OPEN_FOR seconds.
      #
      # @return [void]
      def trip!
        @lock.synchronize { @tripped_at = clock }
      end

      private

      def tripped?
        @lock.synchronize { @tripped_at && clock - @tripped_at < OPEN_FOR }
      end

      def connected?
        Client.instance.nc.connected?
      rescue StandardError
        false
      end

      def clock
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end
    end
  end
end
