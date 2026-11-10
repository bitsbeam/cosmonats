# frozen_string_literal: true

module Cosmo
  class Web
    # Keeps the web UI from tying up server threads on an unreachable NATS: it is open, and requests answer at once
    # without touching NATS, while the client is disconnected or for OPEN_FOR seconds after a request failed on a
    # NATS timeout or connection error that the server doesn't answer a round trip after. The first request after
    # that tries NATS again.
    class Circuit
      OPEN_FOR = 10
      PING_TIMEOUT = 1
      ERRORS = [NATS::IO::Timeout, NATS::IO::ConnectError, NATS::IO::ConnectionClosedError,
                NATS::IO::StaleConnectionError].freeze

      # @return [Circuit]
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

      # Tells an unreachable NATS from a request failing on one of ERRORS while NATS is fine: a direct get on a stream
      # that doesn't exist times out, and a request nobody subscribes to fails with +NoRespondersError+, a
      # +ConnectError+.
      #
      # @return [Boolean] whether the server answers a round trip within PING_TIMEOUT
      def reachable?
        Client.instance.nc.flush(PING_TIMEOUT)
        true
      rescue StandardError
        false
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
