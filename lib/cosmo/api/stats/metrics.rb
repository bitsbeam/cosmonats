# frozen_string_literal: true

module Cosmo
  module API
    module Stats
      # Per-day metrics for every job class: runs, failures, and execution and wait time, kept in their own counters
      # stream for +config.metrics.retention+. Workers {#record} executions in memory and the heartbeat {#flush}es them,
      # so a job costs no NATS round trip; a crashed worker loses at most one heartbeat's worth.
      class Metrics < Counter
        STREAM_NAME = "_cosmometrics"
        DESCRIPTION = "Cosmo metrics"
        DAY = 86_400

        def self.instance
          @instance ||= new
        end

        # Each day's counters expire +config.metrics.retention+ after their last update.
        #
        # @return [Hash]
        def self.stream_config
          super.merge(max_age: Config.to_ns(Utils::Duration.parse(Config.metrics.retention)))
        end

        def initialize
          super("jobs")
          @lock = Mutex.new
          @buffer = buffer
        end

        # Adds one execution to the buffer {#flush} writes.
        #
        # @param job_class [String]
        # @param exec_ms [Numeric, nil] how long a successful execution took
        # @param wait_ms [Numeric, nil] time from enqueue to the job's first delivery
        # @param failed [Boolean]
        # @return [void]
        def record(job_class, exec_ms: nil, wait_ms: nil, failed: false)
          key = [Time.now.utc.strftime("%Y%m%d"), job_class.gsub("::", "-")]
          @lock.synchronize do
            totals = @buffer[key]
            failed ? totals[:failed] += 1 : totals[:count] += 1
            totals[:exec_ms] += exec_ms if exec_ms
            next unless wait_ms

            totals[:waited] += 1
            totals[:wait_ms] += wait_ms
          end
        end

        # Writes the buffered executions to the counters and empties the buffer.
        #
        # @return [void]
        def flush
          pending = @lock.synchronize { @buffer.tap { @buffer = buffer } }
          pending.each do |(day, job), totals|
            totals.each { |field, value| increment("#{day}.#{job}.#{field}", by: value.round) if value.positive? }
          end
        end

        # @param days [Integer] today and the days before it
        # @return [Array<Hash>] per job class +:job+, +:count+, +:failed+, +:exec_ms+ and +:wait_ms+ (averages in
        #   milliseconds, nil without data), busiest first
        def summary(days: 1)
          totals = Hash.new { |hash, job| hash[job] = Hash.new(0) }
          read(days).each { |(_, job, field), value| totals[job][field] += value }
          totals.map { |job, sums| row(sums).merge(job: job) }.sort_by { -_1[:count] }
        end

        # @param job_class [String]
        # @param days [Integer]
        # @return [Array<Hash>] one +{ date:, count:, failed:, exec_ms:, wait_ms: }+ per day, oldest first
        def daily(job_class, days: 30)
          sums = Hash.new { |hash, day| hash[day] = Hash.new(0) }
          read(days).each { |(day, job, field), value| sums[day][field] += value if job == job_class }
          dates(days).map { |day| row(sums[day]).merge(date: day) }
        end

        private

        def buffer
          Hash.new { |hash, key| hash[key] = Hash.new(0) }
        end

        def read(days)
          filters = dates(days).map { "#{STREAM_NAME}.#{@namespace}.#{_1}.>" }
          client.last_messages(STREAM_NAME, filters).map do |subject, data|
            day, job, field = subject.split(".").last(3)
            [[day, job.gsub("-", "::"), field.to_sym], Utils::Json.parse(data, default: {})[:val].to_i]
          end
        end

        def dates(days)
          now = Time.now.utc
          (days - 1).downto(0).map { (now - (_1 * DAY)).strftime("%Y%m%d") }
        end

        def row(sums)
          { count: sums[:count], failed: sums[:failed], exec_ms: average(sums[:exec_ms], sums[:count]),
            wait_ms: average(sums[:wait_ms], sums[:waited]) }
        end

        def average(total, count)
          total.fdiv(count).round(1) if count.positive?
        end
      end
    end
  end
end
