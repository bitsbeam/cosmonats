# frozen_string_literal: true

module Cosmo
  class Processor
    STREAM_PAUSED_RECHECK_TTL = 5.0 # Seconds a stream's paused state is cached before re-checking (override via COSMO_STREAM_PAUSED_RECHECK_TTL)
    STREAMS_PAUSED_IDLE_SLEEP = 1.0 # Seconds to sleep when every stream is paused, preventing a tight CPU spin (override via COSMO_STREAMS_PAUSED_IDLE_SLEEP)

    def self.run(...)
      new(...).tap(&:run)
    end

    attr_reader :consumers

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
      @threads << Thread.new { work_loop }
      @threads << Thread.new { schedule_loop } if scheduler?
    end

    def work_loop # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      shutdown = false

      while running?
        break if shutdown

        all_paused = true
        consumers.each do |(subscription, config, processor)|
          break unless running?

          stream_name = config[:stream].to_s
          ttl = ENV.fetch("COSMO_STREAM_PAUSED_RECHECK_TTL", STREAM_PAUSED_RECHECK_TTL).to_f
          if @cache.fetch(stream_name, ttl:) { API::Stream.new(stream_name).paused? }
            Logger.debug "stream #{stream_name} is paused, skipping fetch"
            next
          end

          all_paused = false
          begin
            @pool.post do
              timeout = fetch_timeout(config)
              Logger.debug "fetching #{fetch_subjects(config).inspect}, timeout=#{timeout}"
              messages = lock(stream_name) { fetch(subscription, batch_size: config[:batch_size], timeout:) }
              Logger.debug "fetched (#{messages&.size.to_i}) messages"
              process(messages, processor) if messages&.any?
            end
          rescue Concurrent::RejectedExecutionError
            shutdown = true
            break # pool doesn't accept new jobs, we are shutting down
          end

          break unless running?
        end

        # When every consumer was skipped (all streams paused) there is no
        # blocking fetch call to pace the loop naturally. Sleep briefly to
        # avoid a tight CPU spin without delaying any individual consumer.
        sleep(ENV.fetch("COSMO_STREAMS_PAUSED_IDLE_SLEEP", STREAMS_PAUSED_IDLE_SLEEP).to_f) if all_paused && running?
      end
    end

    def schedule_loop
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

    def scheduler?
      false
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
      nil
    end

    def client
      Client.instance
    end

    def stopwatch
      Utils::Stopwatch.new
    end

    def lock(stream_name, &)
      @locks ||= Hash.new { |h, k| h[k] = Mutex.new }
      @locks[stream_name].synchronize(&)
    end
  end
end
