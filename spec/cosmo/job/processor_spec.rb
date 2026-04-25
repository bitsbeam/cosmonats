# frozen_string_literal: true

RSpec.describe Cosmo::Job::Processor do
  let(:concurrency) { 3 }
  let(:pool)        { Cosmo::Utils::ThreadPool.new(concurrency) }
  let(:running)     { Concurrent::AtomicBoolean.new }
  let(:processor)   { described_class.new(pool, running, {}) }
  let(:results)     { Results.instance }

  around(:example) do |example|
    prepare_streams do
      processor.run
      example.run
      processor.stop
    end
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

        expect(stream_size("dead")).to eq(1)
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
  end
end
