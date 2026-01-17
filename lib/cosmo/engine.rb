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
      Logger.info "Starting processing, hit Ctrl-C to stop"
      @processors = processors.map { it.run(@pool, @running) }

      signal = handler.wait
      Logger.info "Shutting down... (#{signal} received)"
      shutdown
    end

    def shutdown
      @running.make_false
      @pool.shutdown
      Logger.info "Pausing to allow jobs to finish..."
      @pool.wait_for_termination(Config[:timeout])
      Logger.info "Bye!"
    end
  end
end
