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
      @http_server = nil
    end

    def run(type, options)
      handler = Utils::Signal.trap(:INT, :TERM)
      Logger.info "Starting processing, hit Ctrl-C to stop [concurrency=#{@concurrency}]"

      processor_classes = type && PROCESSORS.key?(type.to_sym) ? [PROCESSORS[type.to_sym]] : PROCESSORS.values
      @processors = processor_classes.map { _1.run(@pool, @running, options) }
      if @running.false?
        Logger.warn "Shutting down... (No processors are running)"
        return
      end

      start_http_server

      signal = handler.wait
      Logger.info "Shutting down... (#{signal} received)"
      shutdown
    end

    def running?
      @running.true?
    end

    def shutdown
      @running.make_false
      @http_server&.stop
      @pool.shutdown
      Logger.info "Pausing to allow jobs to finish..."
      @pool.wait_for_termination(Config[:timeout])
      Logger.info "Bye!"
    end

    private

    # HTTPServer is autoloaded, so it's referenced only after the port is checked
    # to keep its optional dependencies (rack, rackup, webrick) unloaded otherwise.
    def start_http_server
      port = Config.dig(:http, :port)
      return unless port

      host = Config.dig(:http, :host) || HTTPServer::DEFAULT_HOST
      @http_server = HTTPServer.new(port: port, host: host).start
    end
  end
end
