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
      @consumers = {}
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

    def fetch_messages(stream_name, batch_size:, timeout:)
      messages = @consumers[stream_name].fetch(batch_size, timeout:)
      block_given? ? yield(messages) : process(stream_name, messages)
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
