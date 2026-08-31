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
      @quiet = Concurrent::AtomicBoolean.new
    end

    def run(type, options)
      handler = Utils::Signal.trap(:INT, :TERM, :TSTP, :CONT, :USR1)
      Logger.info "Starting processing, hit Ctrl-C to stop [concurrency=#{@concurrency}]"

      processor_classes = type && PROCESSORS.key?(type.to_sym) ? [PROCESSORS[type.to_sym]] : PROCESSORS.values
      @processors = processor_classes.map { _1.run(@pool, @running, options, quiet: @quiet) }
      if @running.false?
        Logger.warn "Shutting down... (No processors are running)"
        return
      end

      signal = handle_shutdown(handler)
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

    private

    def handle_shutdown(handler)
      loop do
        signal = handler.wait
        case signal.to_s
        when "TSTP" then quiet
        when "CONT" then unquiet
        when "USR1" then drain_and_exit(handler)
        else return signal
        end
      end
    end

    def quiet
      return unless @quiet.make_true

      Logger.info "Received TSTP, no new jobs will be fetched; finishing in-flight work"
    end

    def unquiet
      return unless @quiet.make_false

      Logger.info "Received CONT, resuming normal fetching"
    end

    def drain_and_exit(handler)
      return unless @quiet.make_true

      Logger.info "Received USR1, no new jobs will be fetched, exiting when work drains"
      Thread.new do
        @pool.wait_idle
        handler.push(:TERM)
      end
    end
  end
end
