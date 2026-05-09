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
      @threads = []
      @consumers = []
      @cache = Utils::TTLCache.new
    end

    def run
      setup
      return unless @consumers.any?

      @running.make_true
      run_loop
    end

    def stop(timeout = Config[:timeout])
      @running.make_false
      @pool.shutdown
      @consumers.each { |(s, _)| s.unsubscribe rescue nil }
      @pool.wait_for_termination(timeout)
      @threads.compact.each { _1.join(timeout) || _1.kill }
      @consumers.clear
      @threads.clear
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

    def fetch(subscription, batch_size:, timeout:)
      subscription.fetch(batch_size, timeout:)
    rescue NATS::Timeout
      # No messages, continue
    rescue StandardError => e
      Logger.error "Snap! Error just happened"
      Logger.error "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"

      backoff = ENV.fetch("COSMO_STREAMS_FETCH_BACKOFF", 5).to_f
      sleep([timeout, backoff].max) # backoff before retry
    end

    def client
      Client.instance
    end

    def stopwatch
      Utils::Stopwatch.new
    end
  end
end
