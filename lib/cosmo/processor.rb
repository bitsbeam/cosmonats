# frozen_string_literal: true

module Cosmo
  class Processor
    STREAM_PAUSED_RECHECK_TTL = "5s" # How long a stream's paused state is cached before re-checking (override via COSMO_STREAM_PAUSED_RECHECK_TTL)
    STREAMS_PAUSED_IDLE_SLEEP = "1s" # How long to sleep when every stream is paused, preventing a tight CPU spin (override via COSMO_STREAMS_PAUSED_IDLE_SLEEP)
    STREAM_EMPTY_BACKOFF_MAX = "5s"  # Max sleep between empty fetches (override via COSMO_STREAM_EMPTY_BACKOFF_MAX)
    QUIET_SLEEP = "5s"               # How long to sleep between checks while in quiet mode (override via COSMO_QUIET_IDLE_SLEEP)

    # Builds a processor and starts it, see {#run}.
    #
    # @return [Processor]
    def self.run(...)
      new(...).tap(&:run)
    end

    # Checks the command-line options this processor understands, before anything is booted or connected.
    #
    # @param _options [Hash]
    # @return [void]
    def self.validate_options!(_options); end

    attr_reader :consumers

    def initialize(pool, running, options, quiet:)
      @pool = pool
      @running = running
      @quiet = quiet
      @options = options
      @threads = []
      @consumers = []
      @cache = Utils::TTLCache.new
      @busy = Concurrent::AtomicFixnum.new
      @in_flight = Concurrent::Map.new
    end

    # Subscribes the consumers and, when there are any, starts fetching in the background.
    #
    # @return [void]
    def run
      setup
      return unless @consumers.any?

      @running.make_true
      run_loop
    end

    # Threads processing fetched messages right now; threads waiting on a fetch don't count.
    #
    # @return [Integer]
    def busy
      @busy.value
    end

    # Hands every message still being processed back to NATS instead of leaving it for +ack_wait+: a job
    # fails its attempt as usual, a stream message is NAK'd with a delay. Meant for a shutdown that timed
    # out, right before the process exits; a job that finishes afterwards can't ack its released message.
    #
    # @return [Integer] number of messages released
    def release
      @in_flight.values.flatten.count { release_message(_1) }
    end

    # Tells NATS every message still being processed is being worked on, restarting its +ack_wait+, so a long job or
    # batch is not redelivered to another worker while this one is still on it.
    #
    # @return [void]
    def touch
      @in_flight.values.flatten.each { _1.in_progress rescue nil }
    end

    # Kills the threads still processing messages and waits up to +timeout+ seconds for each to unwind,
    # so their +ensure+ blocks run while the NATS connection is still up instead of during process exit.
    #
    # @param timeout [Numeric]
    # @return [void]
    def interrupt(timeout)
      threads = @in_flight.keys
      threads.each(&:kill)
      threads.each { _1.join(timeout) }
    end

    # Stops fetching, unsubscribes, and waits up to +timeout+ seconds for in-flight work.
    #
    # @param timeout [Numeric]
    # @return [void]
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

        if quiet?
          sleep(Utils::Duration.parse(ENV.fetch("COSMO_QUIET_IDLE_SLEEP", QUIET_SLEEP)))
          next
        end

        all_empty = true  # every stream is empty
        all_paused = true # every stream is paused
        consumers.each do |(subscription, config, processor)| # rubocop:disable Metrics/BlockLength
          break unless running?

          stream_name = config[:stream].to_s
          ttl = Utils::Duration.parse(ENV.fetch("COSMO_STREAM_PAUSED_RECHECK_TTL", STREAM_PAUSED_RECHECK_TTL))
          if @cache.fetch("#{stream_name}:paused", ttl:) { API::Stream.new(stream_name).paused? }
            Logger.trace "stream #{stream_name} is paused, skipping fetch"
            next
          end
          all_paused = false

          key = backoff_key(config)
          _, skip_t = consumer_state[key]
          if skip_t && Time.now < skip_t
            Logger.trace "#{key} is empty, backing off"
            next
          end
          all_empty = false

          begin
            @pool.post do
              # Re-check, after possibly being blocked on post to thread pool
              _, skip_t = consumer_state[key]
              next if skip_t && Time.now < skip_t

              timeout = fetch_timeout(config)
              Logger.trace "fetching #{fetch_subjects(config).inspect}, timeout=#{timeout}"
              started_at = Time.now
              messages = fetch(subscription, batch_size: config[:batch_size], timeout:)
              Logger.trace "fetched (#{messages&.size.to_i}) messages"
              if messages&.any?
                consumer_state.delete(key)
                track_busy(messages) { process(messages, processor) }
              else
                max_backoff = Utils::Duration.parse(ENV.fetch("COSMO_STREAM_EMPTY_BACKOFF_MAX", STREAM_EMPTY_BACKOFF_MAX))
                consumer_state.compute(key) do |(count, wake_at)|
                  next [count, wake_at] if wake_at && wake_at > started_at

                  count = count.to_i + 1
                  backoff = [timeout * (2**(count - 1)), max_backoff].min
                  [count, Time.now + backoff]
                end
              end
            end
          rescue Concurrent::RejectedExecutionError
            shutdown = true
            break # pool doesn't accept new jobs, we are shutting down
          end
        end

        break unless running?

        if all_paused
          period = Utils::Duration.parse(ENV.fetch("COSMO_STREAMS_PAUSED_IDLE_SLEEP", STREAMS_PAUSED_IDLE_SLEEP))
          Logger.trace "all streams paused, sleep=#{period}"
          sleep(period)
        elsif all_empty
          next_wake = consumer_state.values.filter_map { |_, t| t }.min
          next unless next_wake # entry was deleted concurrently (messages arrived), re-loop immediately

          remaining = [next_wake - Time.now, 0.01].max
          Logger.trace "all streams empty, sleep=#{remaining}"
          sleep(remaining)
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

    def track_busy(messages)
      @busy.increment
      @in_flight[Thread.current] = messages
      yield
    ensure
      @in_flight.delete(Thread.current)
      @busy.decrement
    end

    def release_message(message)
      abandon(message)
      true
    rescue NATS::JetStream::Error::MsgAlreadyAckd
      false
    rescue StandardError => e
      Logger.error "Failed to release message #{message.subject}: #{e.class}: #{e.message}"
      false
    end

    def abandon(...)
      raise NotImplementedError
    end

    def running?
      @running.true?
    end

    def quiet?
      @quiet.true?
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
      Cosmo.handle_error(e, { source: :fetch })

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

    def consumer_state
      @consumer_state ||= Concurrent::Map.new
    end

    def backoff_key(config)
      config[:stream].to_s
    end
  end
end
