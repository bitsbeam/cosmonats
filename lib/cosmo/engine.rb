# frozen_string_literal: true

require "concurrent-ruby"

module Cosmo
  class Engine
    PROCESSORS = {
      jobs: Job::Processor,
      streams: Stream::Processor
    }.freeze

    def self.run(...)
      instance.run(...)
    end

    def self.instance
      @instance ||= new
    end

    def initialize
      @concurrency = Config.fetch(:concurrency, 1)
      @pool = Utils::ThreadPool.new(@concurrency)
      @running = Concurrent::AtomicBoolean.new
    end

    def run(type, options)
      handler = Utils::Signal.trap(:INT, :TERM)
      Logger.info "Starting processing, hit Ctrl-C to stop"

      processor_classes = type && PROCESSORS.key?(type.to_sym) ? [PROCESSORS[type.to_sym]] : PROCESSORS.values
      @processors = processor_classes.map { _1.run(@pool, @running, options) }
      if @running.false?
        Logger.warn "Shutting down... (No processors are running)"
        return
      end

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
