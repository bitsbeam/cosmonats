# frozen_string_literal: true

RSpec.describe Cosmo::Job::Processor do
  let(:concurrency) { 3 }
  let(:pool)        { Cosmo::Utils::ThreadPool.new(concurrency) }
  let(:running)     { Concurrent::AtomicBoolean.new }
  let(:quiet)       { Concurrent::AtomicBoolean.new }
  let(:processor)   { described_class.new(pool, running, {}, quiet: quiet) }
  let(:results)     { Results.instance }
  let(:scheduled_enabled) { true }

  before do
    Cosmo::Config.load("spec/support/cosmo.yml")
    Cosmo.configure { |config| config.scheduled.enabled = scheduled_enabled }
    # Keep the scheduler fetch timeout short so teardown
    # isn't blocked by the default 5-second NATS pull window.
    ENV["COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT"] = "0.5"
    # Keep the empty-stream backoff cap small so re-delivered messages
    # (after a NAK delay) are picked up quickly. Without this the
    # processor can sleep up to 5 s after the NAK delay expires, causing
    # the retry test to exceed its timeout (16 s NAK + 5 s sleep > 20 s).
    ENV["COSMO_STREAM_EMPTY_BACKOFF_MAX"] = "0.5"
    create_streams(Cosmo::Config.dig(:setup, :jobs))
    processor.run
  end

  after do
    processor.stop
    ENV.delete("COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT")
    ENV.delete("COSMO_STREAM_EMPTY_BACKOFF_MAX")
  end

  context "with successful job execution" do
    before do
      stub_const("GreeterJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        def perform(name) = Results.instance << name
      end)
    end

    it "calls perform with the arguments that were published" do
      GreeterJob.perform_async("Alice")
      wait_until(timeout: 5) { results.any? }

      expect(results).to include("Alice")
    end

    it "processes several jobs published to the same stream" do
      %w[Alice Bob Charlie].each { GreeterJob.perform_async(_1) }
      wait_until(timeout: 5) { results.size >= 3 }

      expect(results).to contain_exactly("Alice", "Bob", "Charlie")
    end

    it "forwards every argument to perform intact" do
      stub_const("MultiArgJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        def perform(a, b, c) = Results.instance << { a: a, b: b, c: c } # rubocop:disable Naming/MethodParameterName
      end)

      MultiArgJob.perform_async("hello", 42, true)
      wait_until(timeout: 5) { results.any? }

      expect(results.first).to eq(a: "hello", b: 42, c: true)
    end

    it "stops consuming messages after an explicit shutdown" do
      stub_const("LifecycleJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        def perform(tag) = Results.instance << tag
      end)
      LifecycleJob.perform_async("before-stop")
      wait_until(timeout: 5) { results.include?("before-stop") }

      processor.stop

      expect do
        LifecycleJob.perform_async("after-stop")
        sleep 0.5
      end.not_to change { results.size }.from(1)
    end

    it "exposes enqueued_at, attempt, and scheduled_by on the job instance" do
      stub_const("MetaJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        def perform(tag) = Results.instance << { tag: tag, enqueued_at: enqueued_at, attempt: attempt, scheduled_by: scheduled_by }
      end)

      MetaJob.perform_async("meta")
      wait_until(timeout: 5) { results.any? }

      result = results.first
      expect(result[:tag]).to eq("meta")
      expect(result[:enqueued_at]).to be_within(5).of(Time.now)
      expect(result[:attempt]).to eq(1)
      expect(result[:scheduled_by]).to be_nil
    end

    it "has subscriptions for all configured priority tiers and processes jobs from each" do
      %w[default high critical low].each do |stream_name|
        stub_const("#{stream_name.capitalize}TierJob", Class.new do
          include Cosmo::Job

          options stream: stream_name.to_sym, retry: 0

          define_method(:perform) { |*| Results.instance << stream_name }
        end)
      end

      Object.const_get("DefaultTierJob").perform_async
      Object.const_get("HighTierJob").perform_async
      Object.const_get("CriticalTierJob").perform_async
      Object.const_get("LowTierJob").perform_async

      wait_until(timeout: 5) { results.size >= 4 }
      expect(results).to contain_exactly("default", "high", "critical", "low")
    end

    context "with a stream filter (--streams)" do
      let(:processor) { described_class.new(pool, running, { streams: ["default"] }, quiet: quiet) }

      it "only subscribes to the given streams, leaving jobs on other streams unconsumed" do
        stub_const("FilteredDefaultJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform(tag) = Results.instance << tag
        end)
        stub_const("FilteredHighJob", Class.new do
          include Cosmo::Job

          options stream: :high, retry: 0

          def perform(tag) = Results.instance << tag
        end)

        FilteredDefaultJob.perform_async("in-scope")
        FilteredHighJob.perform_async("out-of-scope")

        wait_until(timeout: 5) { results.include?("in-scope") }
        sleep 0.5

        expect(results).to eq(["in-scope"])
        expect(stream_size("high")).to eq(1)
      end
    end

    context "with a stream filter (COSMO_JOBS_STREAMS)" do
      let(:processor) { described_class.new(pool, running, {}, quiet: quiet) }

      around do |example|
        ENV["COSMO_JOBS_STREAMS"] = "default"
        example.run
        ENV.delete("COSMO_JOBS_STREAMS")
      end

      it "only subscribes to the streams the variable names" do
        stub_const("EnvDefaultJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform(tag) = Results.instance << tag
        end)
        stub_const("EnvHighJob", Class.new do
          include Cosmo::Job

          options stream: :high, retry: 0

          def perform(tag) = Results.instance << tag
        end)

        EnvDefaultJob.perform_async("in-scope")
        EnvHighJob.perform_async("out-of-scope")

        wait_until(timeout: 5) { results.include?("in-scope") }
        sleep 0.5

        expect(results).to eq(["in-scope"])
        expect(stream_size("high")).to eq(1)
      end
    end

    context "with an unknown stream in the filter" do
      it "raises instead of subscribing to nothing" do
        filtered = described_class.new(pool, running, { streams: %w[default nope] }, quiet: quiet)

        expect { filtered.run }.to raise_error(Cosmo::UnknownJobStreamError, /`nope`.+`default`/)
      end
    end

    context "with the scheduled stream in the filter" do
      let(:processor) { described_class.new(pool, running, { streams: %w[default scheduled] }, quiet: quiet) }

      it "ignores the service stream and subscribes to the rest" do
        stub_const("AlongsideServiceStreamJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform(tag) = Results.instance << tag
        end)

        AlongsideServiceStreamJob.perform_async("in-scope")
        wait_until(timeout: 5) { results.any? }

        expect(results).to eq(["in-scope"])
      end
    end

    context "with the scheduler turned off (--no-scheduler)" do
      let(:processor) { described_class.new(pool, running, { scheduler: false }, quiet: quiet) }

      it "leaves a due scheduled job undispatched" do
        stub_const("UndispatchedJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform(...) = Results.instance << :dispatched
        end)

        UndispatchedJob.perform_at(Time.now - 120, "past-due")
        sleep 1

        expect(results).to be_empty
        expect(stream_size("scheduled")).to eq(1)
      end
    end

    context "with scheduler" do
      before do
        stub_const("OverdueJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform(tag) = Results.instance << "dispatched:#{tag}"
        end)
      end

      it "executes a job whose scheduled execution time is in the past" do
        OverdueJob.perform_at(Time.now - 120, "past-due")
        wait_until(timeout: 12) { results.any? }
        expect(results).to include("dispatched:past-due")
      end

      it "does not execute a job whose execution time is far in the future" do
        stub_const("DistantFutureJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform(...) = Results.instance << :future_ran
        end)

        DistantFutureJob.perform_in(3600, "not yet") # 1 hour from now
        sleep 1 # give the scheduler loop time to inspect and nack the message

        expect(results).not_to include(:future_ran)
        expect(stream_size("scheduled")).to eq(1)
        expect(stream_size("default")).to eq(0)
      end
    end

    context "with scheduling turned off" do
      let(:scheduled_enabled) { false }

      before do
        stub_const("LaterJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform(...) = nil
        end)
      end

      it "runs no scheduler and refuses delayed jobs and crons" do
        expect(processor.subscriptions).not_to include("scheduled")
        expect { LaterJob.perform_in(60, "later") }.to raise_error(Cosmo::SchedulingDisabledError)
        expect { Cosmo::API::Cron.instance.upsert!(class_name: "LaterJob", stream: "default", schedule: "@daily", name: "later") }
          .to raise_error(Cosmo::SchedulingDisabledError)
      end
    end

    context "with a cron schedule" do
      before do
        stub_const("CronReportJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform(tag) = Results.instance << { tag: tag, scheduled_by: scheduled_by }
        end)

        Cosmo::API::Cron.instance.upsert!(class_name: "CronReportJob", stream: "default",
                                          schedule: "@every 1s", args: ["nightly"])
      end

      it "dispatches the fired schedule to the stream that runs the job" do
        wait_until(timeout: 15) { results.any? }

        expect(results.first).to eq({ tag: "nightly", scheduled_by: "cosmo.cron.default.cron_report_job" })
      end

      it "keeps the schedule deployed after it fires" do
        wait_until(timeout: 15) { results.any? }

        expect(Cosmo::API::Cron.instance.all).to include(
          hash_including(class: "CronReportJob", stream: "default", schedule: "@every 1s",
                         schedule_subject: "cosmo.cron.default.cron_report_job",
                         dispatch_subject: "jobs.default.cron_report_job")
        )
      end

      it "reports the firing time as enqueued_at, not the time the scheduler dispatched it" do
        processor.stop

        stub_const("LateCronJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform(tag) = Results.instance << { tag: tag, enqueued_at: enqueued_at, ran_at: Time.now }
        end)

        Cosmo::API::Cron.instance.upsert!(class_name: "LateCronJob", stream: "default",
                                          schedule: "@every 1s", args: ["late"])
        sleep 3

        pool = Cosmo::Utils::ThreadPool.new(concurrency)
        late_processor = described_class.new(pool, Concurrent::AtomicBoolean.new, {},
                                             quiet: Concurrent::AtomicBoolean.new)
        late_processor.run

        begin
          wait_until(timeout: 15) { results.any? { _1.is_a?(Hash) && _1[:tag] == "late" } }
        ensure
          late_processor.stop
        end

        fired = results.find { _1.is_a?(Hash) && _1[:tag] == "late" }
        expect(fired[:ran_at] - fired[:enqueued_at]).to be > 2
      end
    end

    context "with limit options" do
      let(:concurrency) { 5 }

      around(:example) do |example|
        Cosmo::Job::Limit.instance_variable_set(:@instance, nil)
        example.run
        Cosmo::Job::Limit.instance_variable_set(:@instance, nil)
      end

      context "with a global concurrency limit" do
        before do
          stub_const("SlowConcurrentJob", Class.new do
            include Cosmo::Job

            options stream: :default, retry: 0, limit: { duration: 2, concurrency: 2 }

            def perform(id)
              Results.instance << "start:#{id}"
              sleep 0.5
              Results.instance << "end:#{id}"
            end
          end)
        end

        it "allows up to the limit to run concurrently and queues the rest" do
          4.times { |i| SlowConcurrentJob.perform_async(i) }

          wait_until(timeout: 15) { results.count { _1.start_with?("end:") } >= 4 }

          first_end_idx = results.index { _1.start_with?("end:") }
          starts_before_first_end = results[0...first_end_idx].count { _1.start_with?("start:") }
          expect(starts_before_first_end).to be <= 2
        end
      end

      context "with a key-scoped concurrency limit" do
        before do
          stub_const("PerUserConcurrentJob", Class.new do
            include Cosmo::Job

            options stream: :default, retry: 0,
                    limit: { duration: 2, concurrency: { to: 1, key: ->(user_id) { user_id } } }

            def perform(user_id)
              Results.instance << "start:#{user_id}"
              sleep 0.4
              Results.instance << "end:#{user_id}"
            end
          end)
        end

        it "allows parallel execution for different keys" do
          PerUserConcurrentJob.perform_async("user-A")
          PerUserConcurrentJob.perform_async("user-B")

          wait_until(timeout: 10) { results.count { _1.start_with?("end:") } >= 2 }

          expect(results).to include("start:user-A", "end:user-A", "start:user-B", "end:user-B")
        end

        it "serialises two jobs for the same key" do
          2.times { PerUserConcurrentJob.perform_async("user-X") }

          wait_until(timeout: 15) { results.count { _1 == "end:user-X" } >= 2 }

          ends   = results.each_with_index.filter_map { |r, i| i if r == "end:user-X" }
          starts = results.each_with_index.filter_map { |r, i| i if r == "start:user-X" }

          expect(starts.size).to eq(2)
          expect(ends.size).to eq(2)
          expect(ends.first).to be < starts.last
        end
      end

      context "with a duration limit (execution timeout)" do
        before do
          stub_const("SlowJob", Class.new do
            include Cosmo::Job

            options stream: :default, retry: 0, dead: true, limit: { duration: 1 }

            def perform = sleep(30)
          end)
        end

        it "kills the job after duration and moves it to DLQ" do
          started_at = Time.now
          SlowJob.perform_async
          wait_until(timeout: 8) { stream_size("dead") >= 1 }

          expect(Time.now - started_at).to be < 5
          expect(stream_size("dead")).to eq(1)
          expect(stream_size("default")).to eq(0)
        end

        it "records the timeout as the dead job error" do
          SlowJob.perform_async
          wait_until(timeout: 8) { stream_size("dead") >= 1 }

          job = Cosmo::API::Stream.new("dead").messages.first
          expect(job.error_class).to eq("Timeout::Error")
          expect(job.error_message).to eq("execution expired after the 1s duration limit")
          expect(job.error_backtrace).not_to be_nil
        end
      end
    end
  end

  context "with failed job execution" do
    context "with dead letter queue" do
      it "moves the failing job to DLQ" do
        stub_const("ImmediatelyDeadJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0, dead: true

          def perform(...) = raise "intentional failure"
        end)
        expect(stream_size("dead")).to eq(0)

        ImmediatelyDeadJob.perform_async("trigger")
        wait_until(timeout: 5) { stream_size("dead") >= 1 }
        expect(stream_size("default")).to eq(0)
      end

      it "records the raised exception as the dead job error" do
        stub_const("ExplainedDeadJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0, dead: true

          def perform(...) = raise ArgumentError, "intentional failure"
        end)

        ExplainedDeadJob.perform_async("trigger")
        wait_until(timeout: 5) { stream_size("dead") >= 1 }

        job = Cosmo::API::Stream.new("dead").messages.first
        expect(job.error_class).to eq("ArgumentError")
        expect(job.error_message).to eq("intentional failure")
        expect(job.error_backtrace).to include("processor_spec.rb")
      end

      it "treats retry: false as retry: 0 and moves the failing job straight to DLQ" do
        stub_const("NoRetryJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: false, dead: true

          def perform(...) = raise "intentional failure"
        end)
        expect(stream_size("dead")).to eq(0)

        NoRetryJob.perform_async("trigger")
        wait_until(timeout: 5) { stream_size("dead") >= 1 }
        expect(stream_size("default")).to eq(0)
      end

      it "retries a failing job and moves it to the DLQ" do
        stub_const("RetryableJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 1, dead: true

          def perform
            Results.instance << "attempt-#{Results.instance.counter}"
            Results.instance.increment

            raise StandardError, "still broken"
          end
        end)

        RetryableJob.perform_async

        wait_until(timeout: 5) { results.any? }
        expect(results).to eq(["attempt-0"])

        # First attempt lands quickly, the second arrives after NATS backoff ~16s.
        wait_until(timeout: 20) { stream_size("dead") >= 1 }
        expect(results).to eq(%w[attempt-0 attempt-1])
        expect(stream_size("dead")).to eq(1)
      end

      it "uses the job class's custom retry_in handler, passing it the attempt count and exception" do
        stub_const("CustomRetryInJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 1, dead: true, retry_in: lambda { |count, exception|
            Results.instance << { count: count, message: exception.message }
            1
          }

          def perform
            raise StandardError, "still broken"
          end
        end)

        CustomRetryInJob.perform_async

        # With the default backoff this would take ~16s; the custom retry_in returns 1s.
        wait_until(timeout: 5) { stream_size("dead") >= 1 }
        expect(results).to eq([{ count: 1, message: "still broken" }])
        expect(stream_size("dead")).to eq(1)
      end

      it "falls back to the default backoff when retry_in raises or returns garbage" do
        stub_const("BrokenRetryInJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 1, dead: true, retry_in: ->(count, _exception) { count.odd? ? "not a number" : (raise "boom") }

          def perform
            Results.instance << "attempt-#{Results.instance.counter}"
            Results.instance.increment

            raise StandardError, "still broken"
          end
        end)

        BrokenRetryInJob.perform_async

        wait_until(timeout: 5) { results.any? }
        expect(results).to eq(["attempt-0"])

        # Both the "not a number" and the raising cases fall back to the default ~16s backoff.
        wait_until(timeout: 20) { stream_size("dead") >= 1 }
        expect(results).to eq(%w[attempt-0 attempt-1])
        expect(stream_size("dead")).to eq(1)
      end

      it "skips a malformed JSON payload and keeps processing" do
        stub_const("CanaryJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform = Results.instance << :canary_ok
        end)
        client.publish("jobs.default.garbage_payload", "THIS_IS_NOT_JSON", header: { "Nats-Msg-Id" => "bad-json-1" })
        client.publish("jobs.default.canary_job", %({"class":"CanaryJob","jid":"abc","args":[]}), header: { "Nats-Msg-Id" => "abc" })

        wait_until(timeout: 5) { stream_size("default").zero? }
        expect(results).to include(:canary_ok)
      end

      it "skips an unknown job class and keeps processing" do
        stub_const("CanaryJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0

          def perform = Results.instance << :canary_ok
        end)
        payload = Cosmo::Utils::Json.dump({ jid: "unknown-class-test", class: "AbsolutelyNonExistentJobXYZ", args: [], retry: 0, dead: false })
        client.publish("jobs.default.absolutely_non_existent_job_xyz", payload, header: { "Nats-Msg-Id" => "bad-class-1" })
        client.publish("jobs.default.canary_job", %({"class":"CanaryJob","jid":"abc","args":[]}), header: { "Nats-Msg-Id" => "abc" })

        wait_until(timeout: 5) { stream_size("default").zero? }
        expect(results).to eq([:canary_ok])
      end
    end

    context "without dead letter queue" do
      it "terminates the message" do
        stub_const("TerminatedJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0, dead: false

          def perform(...) = raise "intentional failure"
        end)

        TerminatedJob.perform_async("trigger")
        wait_until(timeout: 5) { stream_size("default").zero? }

        expect(stream_size("dead")).to eq(0)
      end
    end

    context "with dead-lettering turned off" do
      it "drops a job that gives up instead of parking it" do
        Cosmo.configure { |config| config.dead.enabled = false }
        stub_const("UnparkedJob", Class.new do
          include Cosmo::Job

          options stream: :default, retry: 0, dead: true

          def perform(...) = raise "intentional failure"
        end)

        UnparkedJob.perform_async("trigger")
        wait_until(timeout: 5) { stream_size("default").zero? }

        expect(stream_size("dead")).to eq(0)
      end
    end
  end

  context "with server middleware" do
    let(:tracer) do
      Class.new do
        def initialize(tag) = @tag = tag

        def call(job, data, message)
          Results.instance << [@tag, job.class.name, data[:jid] == job.jid, message.metadata.stream]
          yield
        end
      end
    end

    before do
      stub_const("GreeterJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        def perform(name) = Results.instance << name
      end)
      stub_const("FailingJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 1, dead: true

        def perform(...) = raise "intentional failure"
      end)
    end

    it "runs every registered middleware around perform, outermost first" do
      Cosmo.configure do |config|
        config.server_middleware do |chain|
          chain.add(Class.new(tracer), :outer)
          chain.add(Class.new(tracer), :inner)
        end
      end

      GreeterJob.perform_async("Alice")
      wait_until(timeout: 5) { results.include?("Alice") }

      expect(results).to eq([[:outer, "GreeterJob", true, "default"], [:inner, "GreeterJob", true, "default"], "Alice"])
    end

    it "acks the job without performing it when a middleware does not yield" do
      Cosmo::Config.server_middleware.add(Class.new { def call(*) = Results.instance << :skipped })

      GreeterJob.perform_async("Alice")
      wait_until(timeout: 5) { results.include?(:skipped) && stream_size("default").zero? }

      expect(results).to eq([:skipped])
      expect(stream_size("dead")).to eq(0)
    end

    it "dead-letters the job when a middleware raises" do
      Cosmo::Config.server_middleware.add(Class.new { def call(*) = raise("middleware failure") })

      GreeterJob.perform_async("Alice")
      wait_until(timeout: 5) { stream_size("dead") >= 1 }

      expect(results).to be_empty
      expect(Cosmo::API::Stream.new("dead").messages.first.error_message).to eq("middleware failure")
    end

    it "counts every execution in the processed and failed totals" do
      allow(processor).to receive(:default_retry_delay).and_return(0.1)

      GreeterJob.perform_async("Alice")
      FailingJob.perform_async("Bob")
      wait_until(timeout: 10) { stream_size("dead") >= 1 && Cosmo::API::Stats.failed == 2 }

      expect(Cosmo::API::Stats.processed).to eq(1)
    end

    it "hands every failed attempt to the error handlers with the job's context" do
      allow(processor).to receive(:default_retry_delay).and_return(0.1)
      Cosmo.configure { |config| config.error_handlers << ->(error, context) { Results.instance << [error.message, context] } }

      FailingJob.perform_async("Bob")
      wait_until(timeout: 10) { stream_size("dead") >= 1 }

      expect(results.map(&:first)).to eq(["intentional failure", "intentional failure"])
      expect(results.map { _2[:attempt] }).to eq([1, 2])
      expect(results.first.last).to include(source: :job, class: "FailingJob", args: ["Bob"], stream: "default",
                                            subject: "jobs.default.failing_job", jid: a_kind_of(String))
    end

    it "hands a message for an unknown job class to the error handlers" do
      Cosmo.configure { |config| config.error_handlers << ->(error, context) { Results.instance << [error.message, context] } }
      payload = Cosmo::Utils::Json.dump({ jid: "ghost-1", class: "GhostJobXYZ", args: [], retry: 0, dead: true })

      client.publish("jobs.default.ghost_job_xyz", payload, header: { "Nats-Msg-Id" => "ghost-1" })
      wait_until(timeout: 5) { results.any? }

      expect(results.first.first).to eq("GhostJobXYZ class not found")
      expect(results.first.last).to include(source: :reject, class: "GhostJobXYZ", stream: "default")
    end

    it "keeps processing when an error handler raises" do
      Cosmo.configure do |config|
        config.error_handlers << ->(*) { raise "handler down" }
        config.error_handlers << ->(error, _) { Results.instance << error.message }
      end

      GreeterJob.perform_async("Alice")
      FailingJob.perform_async("Bob")
      wait_until(timeout: 10) { results.include?("Alice") && results.include?("intentional failure") }
    end

    it "redelivers a job a middleware requeues, without counting it as failed" do
      Cosmo.configure do |config|
        config.server_middleware.prepend(Class.new do
          def call(job, *)
            raise Cosmo::Job::Requeue, 0.2 if job.attempt == 1

            yield
          end
        end)
      end

      GreeterJob.perform_async("Alice")
      wait_until(timeout: 5) { results.include?("Alice") }

      expect(Cosmo::API::Stats.failed).to eq(0)
      expect(stream_size("dead")).to eq(0)
    end
  end

  context "with Sentry integration" do
    let(:transport) { Sentry.get_current_client.transport }

    before(:all) do
      require "sentry-ruby"
      require "cosmo/middleware/sentry"

      Sentry.init do |config|
        config.dsn = "http://12345:67890@sentry.localdomain/sentry/42"
        config.background_worker_threads = 0
        config.traces_sample_rate = 1.0
        config.transport.transport_class = Sentry::DummyTransport
      end
    end

    before do
      transport.events.clear
      Cosmo::Config.server_middleware.add(Cosmo::Middleware::Sentry)
      Cosmo::Config.error_handlers << Cosmo::Middleware::Sentry::ERROR_HANDLER

      stub_const("GreeterJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        def perform(name) = Results.instance << name
      end)

      stub_const("GreeterJobFail", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        def perform(_name) = raise "Boom!"
      end)
    end

    it "calls successfully" do
      GreeterJob.perform_async("Alice")
      wait_until(timeout: 5) { results.any? }

      expect(results).to include("Alice")
      expect(transport.events).not_to be_empty
      expect(transport.events.last.contexts[:trace]).to include(
        status: "ok",
        origin: "auto.queue.cosmonats",
        op: "queue.cosmonats"
      )
      expect(transport.events.last.contexts[:trace][:data]).to include(
        "messaging.message.id" => be_kind_of(String),
        "messaging.destination.name" => "default:jobs.default.greeter_job",
        "messaging.message.retry.count" => 0,
        "http.response.status_code" => 200
      )
    end

    it "handles error" do
      GreeterJobFail.perform_async("Alice")
      wait_until(timeout: 5) { transport.events.size > 1 }

      error = transport.events.find { _1.instance_of?(Sentry::ErrorEvent) }
      expect(error.contexts[:cosmonats]).to include(
        source: :job,
        class: "GreeterJobFail",
        args: ["Alice"],
        stream: "default",
        subject: "jobs.default.greeter_job_fail",
        attempt: 1
      )
      expect(error.contexts[:trace]).to include(trace_id: a_kind_of(String), span_id: a_kind_of(String))
      expect(error.exception.values.first.type).to eq("RuntimeError")
      expect(error.exception.values.first.value).to match("Boom!")

      error = transport.events.find { _1.instance_of?(Sentry::TransactionEvent) }
      expect(error.contexts[:trace]).to include(status: "internal_error", origin: "auto.queue.cosmonats", op: "queue.cosmonats")
      expect(error.contexts[:trace]).to include(trace_id: a_kind_of(String), span_id: a_kind_of(String))
      expect(error.contexts[:trace][:data]).to include(
        "messaging.message.id" => be_kind_of(String),
        "messaging.destination.name" => "default:jobs.default.greeter_job_fail",
        "messaging.message.retry.count" => 0,
        "http.response.status_code" => 500
      )
    end
  end
end
