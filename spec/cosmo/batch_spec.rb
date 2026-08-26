# frozen_string_literal: true

RSpec.describe Cosmo::Batch do
  let(:concurrency) { 5 }
  let(:pool)        { Cosmo::Utils::ThreadPool.new(concurrency) }
  let(:running)     { Concurrent::AtomicBoolean.new }
  let(:processor)   { Cosmo::Job::Processor.new(pool, running, {}) }
  let(:results)     { Results.instance }

  before do
    Cosmo::Config.load("spec/support/cosmo.yml")
    ENV["COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT"] = "0.5"
    ENV["COSMO_STREAM_EMPTY_BACKOFF_MAX"] = "0.5"
    create_streams(Cosmo::Config.dig(:setup, :jobs))
    processor.run

    stub_const("BatchWorkerJob", Class.new do
      include Cosmo::Job

      options stream: :default, retry: 0

      def perform(tag) = Results.instance << { tag: tag }
    end)

    stub_const("BatchFailingJob", Class.new do
      include Cosmo::Job

      options stream: :default, retry: 0, dead: true

      def perform(tag) = raise "boom:#{tag}"
    end)

    stub_const("CompleteCallback", Class.new do
      def on_complete(status, opts)
        Results.instance << { event: :complete, bid: status[:bid], stats: status.reject { |k| k == :bid }, opts: opts }
      end
    end)

    stub_const("SuccessCallback", Class.new do
      def on_success(status, opts)
        Results.instance << { event: :success, bid: status[:bid], stats: status.reject { |k| k == :bid }, opts: opts }
      end
    end)
  end

  after do
    processor.stop
    ENV.delete("COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT")
    ENV.delete("COSMO_STREAM_EMPTY_BACKOFF_MAX")
  end

  def callback_event(event, bid)
    results.find { _1.is_a?(Hash) && _1[:event] == event && _1[:bid] == bid }
  end

  it "fires :complete once every job finishes successfully, with accurate stats" do
    batch = described_class.new
    batch.jobs do
      BatchWorkerJob.perform_async("a")
      BatchWorkerJob.perform_async("b")
    end
    batch.on(:complete, CompleteCallback, user_id: 1)

    wait_until(timeout: 5) { callback_event(:complete, batch.bid) }

    event = callback_event(:complete, batch.bid)
    expect(event[:stats]).to eq(total: 2, succeeded: 2, failed: 0)
    expect(event[:opts]).to eq(user_id: 1)
  end

  it "fires :success when every job succeeds" do
    batch = described_class.new
    batch.jobs { BatchWorkerJob.perform_async("a") }
    batch.on(:success, SuccessCallback)

    wait_until(timeout: 5) { callback_event(:success, batch.bid) }
    expect(callback_event(:success, batch.bid)[:stats]).to eq(total: 1, succeeded: 1, failed: 0)
  end

  it "fires :complete but not :success when a job terminally fails (DLQ'd)" do
    batch = described_class.new
    batch.jobs do
      BatchWorkerJob.perform_async("ok")
      BatchFailingJob.perform_async("bad")
    end
    batch.on(:complete, CompleteCallback)
    batch.on(:success, SuccessCallback)

    wait_until(timeout: 5) { callback_event(:complete, batch.bid) }
    expect(callback_event(:complete, batch.bid)[:stats]).to eq(total: 2, succeeded: 1, failed: 1)

    sleep 0.5 # give a spurious :success dispatch a chance to show up, if the bug exists
    expect(callback_event(:success, batch.bid)).to be_nil
  end

  it "fires immediately for an empty batch" do
    batch = described_class.new
    batch.jobs {}
    batch.on(:complete, CompleteCallback)
    batch.on(:success, SuccessCallback)

    wait_until(timeout: 5) { callback_event(:complete, batch.bid) }
    expect(callback_event(:complete, batch.bid)[:stats]).to eq(total: 0, succeeded: 0, failed: 0)
    wait_until(timeout: 5) { callback_event(:success, batch.bid) }
  end

  it "fires a callback registered after the batch has already finished" do
    batch = described_class.new
    batch.jobs { BatchWorkerJob.perform_async("fast") }

    # Wait on the actual "batch has finished" condition instead of guessing at timing with
    # a fixed sleep - a sleep long enough on a fast dev machine isn't guaranteed to be long
    # enough once the processor is competing for CPU/NATS with the rest of the suite.
    wait_until(timeout: 5) { described_class.send(:kv).get("#{batch.bid}.finalized") }

    batch.on(:complete, CompleteCallback, late: true)

    wait_until(timeout: 5) { callback_event(:complete, batch.bid) }
    expect(callback_event(:complete, batch.bid)[:opts]).to eq(late: true)
  end

  it "does not double-fire when #on is called twice for the same event" do
    batch = described_class.new
    batch.jobs { BatchWorkerJob.perform_async("once") }
    batch.on(:complete, CompleteCallback, attempt: 1)
    batch.on(:complete, CompleteCallback, attempt: 2)

    wait_until(timeout: 5) { callback_event(:complete, batch.bid) }
    sleep 0.5
    expect(results.count { _1.is_a?(Hash) && _1[:event] == :complete && _1[:bid] == batch.bid }).to eq(1)
  end

  it "rolls back the pending count when a job never actually publishes" do
    call_count = 0
    allow(Cosmo::Publisher).to receive(:publish_job).and_wrap_original do |original, data|
      call_count += 1
      raise Cosmo::StreamNotFoundError, "no such stream" if call_count == 1

      original.call(data)
    end

    batch = described_class.new
    expect do
      batch.jobs { BatchWorkerJob.perform_async("never-published") }
    end.to raise_error(Cosmo::StreamNotFoundError)

    batch.on(:complete, CompleteCallback, marker: "rollback")

    wait_until(timeout: 5) { callback_event(:complete, batch.bid) }
    expect(callback_event(:complete, batch.bid)[:stats]).to eq(total: 0, succeeded: 0, failed: 0)
  end

  it "tracks a scheduled job (perform_at) added inside a batch" do
    batch = described_class.new
    batch.jobs { BatchWorkerJob.perform_at(Time.now - 5, "overdue") }
    batch.on(:complete, CompleteCallback)

    wait_until(timeout: 10) { callback_event(:complete, batch.bid) }
    expect(callback_event(:complete, batch.bid)[:stats]).to eq(total: 1, succeeded: 1, failed: 0)
  end

  it "does not track perform_async calls made outside a #jobs block" do
    batch = described_class.new
    BatchWorkerJob.perform_async("untracked")
    batch.on(:complete, CompleteCallback, marker: "outside-jobs-block")

    wait_until(timeout: 5) { results.any? { _1.is_a?(Hash) && _1[:tag] == "untracked" } }
    sleep 0.5
    expect(callback_event(:complete, batch.bid)).to be_nil
  end

  it "accepts a caller-supplied bid instead of generating one" do
    batch = described_class.new(bid: "custom-bid")
    batch.jobs { BatchWorkerJob.perform_async("custom") }
    batch.on(:complete, CompleteCallback)

    expect(batch.bid).to eq("custom-bid")
    wait_until(timeout: 5) { callback_event(:complete, "custom-bid") }
    expect(callback_event(:complete, "custom-bid")[:stats]).to eq(total: 1, succeeded: 1, failed: 0)
  end

  context "nested batches" do
    before do
      stub_const("NestingJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        # Cosmo::Job threads perform_async's args through as a plain positional
        # array (no keyword-argument support), so fail_child is positional here.
        # rubocop:disable Style/OptionalBooleanParameter
        def perform(tag, fail_child = false)
          child = Cosmo::Batch.new(parent: batch_id)
          child.jobs do
            fail_child ? BatchFailingJob.perform_async("child-of-#{tag}") : BatchWorkerJob.perform_async("child-of-#{tag}")
          end
          Results.instance << { tag: tag }
        end
        # rubocop:enable Style/OptionalBooleanParameter
      end)
    end

    it "only completes the parent once a nested batch created inside a job also completes" do
      parent = described_class.new
      parent.jobs { NestingJob.perform_async("root") }
      parent.on(:complete, CompleteCallback)
      parent.on(:success, SuccessCallback)

      # total: 1 for NestingJob itself, +1 for the child batch it spawns --
      # the parent only reaches :complete once both are done.
      wait_until(timeout: 5) { callback_event(:complete, parent.bid) }
      expect(callback_event(:complete, parent.bid)[:stats]).to eq(total: 2, succeeded: 2, failed: 0)
      wait_until(timeout: 5) { callback_event(:success, parent.bid) }
    end

    it "propagates a failure inside a nested batch up to the parent as a single failure unit" do
      parent = described_class.new
      parent.jobs { NestingJob.perform_async("root", true) }
      parent.on(:complete, CompleteCallback)
      parent.on(:success, SuccessCallback)

      wait_until(timeout: 5) { callback_event(:complete, parent.bid) }
      expect(callback_event(:complete, parent.bid)[:stats]).to eq(total: 2, succeeded: 1, failed: 1)

      sleep 0.5
      expect(callback_event(:success, parent.bid)).to be_nil
    end

    it "cascades through three levels of nesting" do
      stub_const("GrandparentNestingJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        def perform
          child = Cosmo::Batch.new(parent: batch_id)
          child.jobs { NestingJob.perform_async("mid") }
          Results.instance << { tag: "grandparent" }
        end
      end)

      root = described_class.new
      root.jobs { GrandparentNestingJob.perform_async }
      root.on(:complete, CompleteCallback)

      # total: 1 for GrandparentNestingJob itself, +1 for the batch it spawns,
      # which in turn only completes once NestingJob and its own spawned
      # batch (2 more levels down) both finish.
      wait_until(timeout: 5) { callback_event(:complete, root.bid) }
      expect(callback_event(:complete, root.bid)[:stats]).to eq(total: 2, succeeded: 2, failed: 0)
    end
  end
end
