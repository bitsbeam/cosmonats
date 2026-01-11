# frozen_string_literal: true

require "concurrent-ruby"

module Cosmo
  class Engine
    def self.run
      instance.run
    end

    def self.instance
      @instance ||= new
    end

    def initialize
      @concurrency = Config.fetch(:concurrency, 1)
      @pool = Utils::ThreadPool.new(@concurrency)
      @running = Concurrent::AtomicBoolean.new
    end

    def run(processors = [Job::Processor, Stream::Processor])
      handler = Utils::Signal.trap(:INT, :TERM)
      @processors = processors.map { it.run(@pool, @running) }

      signal = handler.wait
      puts "Shutting down... (#{signal} received)"
      shutdown
    end

    def shutdown
      @running.make_false
      @pool.shutdown
      @pool.wait_for_termination(Config[:timeout])
    end
  end
end
