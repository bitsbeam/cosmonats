# frozen_string_literal: true

require "socket"
require "shellwords"

module Cosmo
  # Publishes this process's identity and live state to API::Stats::Processes, so the Web UI lists
  # every running worker, the idle ones included.
  class Heartbeat
    INTERVAL = 10

    # @param engine [Engine]
    # @param options [Hash] the parsed command options
    def initialize(engine, options: {})
      @engine = engine
      @options = options
      @started_at = Time.now.to_i
    end

    # Registers the process and keeps refreshing it every INTERVAL seconds.
    #
    # @return [self]
    def start
      beat
      @thread = Thread.new do
        loop do
          sleep(INTERVAL)
          beat
          flush
        end
      end
      self
    end

    # Stops beating and removes the entry right away, instead of leaving it to expire.
    #
    # @return [void]
    def stop
      @thread&.kill&.join
      @thread = nil
      flush
      processes.unregister(identity)
    rescue StandardError => e
      Logger.debug "Heartbeat unregister error: #{e.class} #{e.message}"
    end

    # Writes the current state now, e.g. right after it changes.
    #
    # @return [void]
    def beat
      processes.register(identity, info)
    rescue StandardError => e
      Logger.debug "Heartbeat error: #{e.class} #{e.message}"
    end

    # Writes the job metrics recorded since the last flush.
    #
    # @return [void]
    def flush
      API::Stats::Metrics.instance.flush if Config.metrics.enabled
    rescue StandardError => e
      Logger.debug "Metrics flush error: #{e.class} #{e.message}"
    end

    # @return [String]
    def identity
      @identity ||= "#{Socket.gethostname}-#{::Process.pid}"
    end

    # @return [Hash] everything the Web UI shows about this process
    def info
      static_info.merge(
        state: @engine.state,
        busy: @engine.busy,
        subscriptions: @engine.subscriptions,
        rss: rss,
        nats: nats_info,
        beat_at: Time.now.to_i
      )
    end

    private

    def static_info
      @static_info ||= {
        identity: identity,
        hostname: Socket.gethostname,
        pid: ::Process.pid,
        cmdline: [File.basename($PROGRAM_NAME.to_s), *CLI.instance.argv].shelljoin,
        options: @options,
        concurrency: @engine.concurrency,
        timeout: Config[:timeout],
        http_port: Config.dig(:http, :port),
        version: VERSION,
        ruby: "#{RUBY_ENGINE} #{RUBY_VERSION}",
        started_at: @started_at
      }
    end

    def nats_info
      client = Client.instance
      connection = client.nc
      server = connection.server_info
      uri = connection.connected_server
      {
        name: client.name,
        ip: server[:client_ip],
        client_id: server[:client_id],
        server: server[:server_name],
        server_version: server[:version],
        url: uri && "#{uri.host}:#{uri.port}",
        rtt: rtt(connection),
        reconnects: connection.stats[:reconnects]
      }
    end

    # nats-pure has no RTT call, but a flush is a PING/PONG round trip.
    def rtt(connection)
      started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      connection.flush(1)
      ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
    rescue StandardError
      nil
    end

    # Resident memory in KB: from procfs on Linux, from ps elsewhere.
    def rss
      status = "/proc/#{::Process.pid}/status"
      return File.read(status)[/VmRSS:\s+(\d+)/, 1].to_i if File.exist?(status)

      `ps -o rss= -p #{::Process.pid}`.to_i
    rescue StandardError
      nil
    end

    def processes
      API::Stats::Processes.instance
    end
  end
end
