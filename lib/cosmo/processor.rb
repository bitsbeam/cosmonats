# frozen_string_literal: true

module Cosmo
  class Processor
    def self.run(...)
      new(...).tap(&:run)
    end

    def initialize(pool, running, options)
      @pool = pool
      @running = running
      @options = options
      @consumers = []
    end

    def run
      setup
      return unless @consumers.any?

      @running.make_true
      run_loop
    end

    private

    def run_loop
      raise NotImplementedError
    end

    def setup
      raise NotImplementedError
    end

    def process(...)
      raise NotImplementedError
    end

    def running?
      @running.true?
    end

    def fetch_messages(subscription, batch_size:, timeout:)
      subscription.fetch(batch_size, timeout:)
    rescue NATS::Timeout
      # No messages, continue
    end

    def client
      Client.instance
    end

    def stopwatch
      Utils::Stopwatch.new
    end
  end
end
