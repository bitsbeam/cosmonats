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

    # Processor classes a +type+ starts: the matching one, or all of them when it names none.
    #
    # @param type [String, Symbol, nil]
    # @return [Array<Class>]
    def self.processors_for(type)
      type && PROCESSORS.key?(type.to_sym) ? [PROCESSORS[type.to_sym]] : PROCESSORS.values
    end

    def self.instance
      @instance ||= new
    end

    def initialize
      @concurrency = Config.fetch(:concurrency, 1)
      @pool = Utils::ThreadPool.new(@concurrency)
      @running = Concurrent::AtomicBoolean.new
      @quiet = Concurrent::AtomicBoolean.new
      @http_server = nil
    end

    def run(type, options)
      handler = Utils::Signal.trap(:INT, :TERM, :TSTP, :CONT, :USR1, :TTIN)
      Logger.info "Starting processing, hit Ctrl-C to stop [concurrency=#{@concurrency}]"

      @processors = self.class.processors_for(type).map { _1.run(@pool, @running, options, quiet: @quiet) }
      if @running.false?
        Logger.warn "Shutting down... (No processors are running)"
        return
      end

      start_http_server

      signal = handle_shutdown(handler)
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
    # to keep its optional dependencies (rack, webrick) unloaded otherwise.
    def start_http_server
      port = Config.dig(:http, :port)
      return unless port

      host = Config.dig(:http, :host) || HTTPServer::DEFAULT_HOST
      @http_server = HTTPServer.new(port: port, host: host).start
    end

    def handle_shutdown(handler)
      loop do
        signal = handler.wait
        case signal.to_s
        when "TSTP" then quiet
        when "CONT" then unquiet
        when "USR1" then drain_and_exit(handler)
        when "TTIN" then dump_threads
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

    def dump_threads
      threads = Thread.list
      Logger.warn "Received TTIN, dumping backtraces of #{threads.size} threads"
      threads.each do |thread|
        backtrace = thread.backtrace || ["<no backtrace available>"]
        tid = (thread.object_id ^ ::Process.pid).to_s(36)
        Logger.warn "Thread tid=#{tid} name=#{thread.name} [#{thread.status}]\n#{backtrace.join("\n")}"
      end
    end
  end
end
