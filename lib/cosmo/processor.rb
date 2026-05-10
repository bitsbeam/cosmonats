# frozen_string_literal: true

module Cosmo
  class Processor
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

        consumers.each do |(subscription, config, processor)|
          break unless running?

          stream_name = config[:stream].to_s
          if @cache.fetch(stream_name, ttl: 5) { API::Stream.new(stream_name).paused? }
            Logger.debug "stream #{stream_name} is paused, skipping fetch"
            next
          end

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
