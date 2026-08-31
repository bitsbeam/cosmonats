# frozen_string_literal: true

RSpec.describe Cosmo::API::Batch do
  let(:concurrency) { 5 }
  let(:pool)        { Cosmo::Utils::ThreadPool.new(concurrency) }
  let(:running)     { Concurrent::AtomicBoolean.new }
  let(:quiet)       { Concurrent::AtomicBoolean.new }
  let(:processor)   { Cosmo::Job::Processor.new(pool, running, {}, quiet: quiet) }
  let(:results)     { Results.instance }

  before do
    Cosmo::Config.load("spec/support/cosmo.yml")
    ENV["COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT"] = "0.5"
    ENV["COSMO_STREAM_EMPTY_BACKOFF_MAX"] = "0.5"
    create_streams(Cosmo::Config.dig(:setup, :jobs))
    processor.run

    stub_const("StatusWorkerJob", Class.new do
      include Cosmo::Job

      options stream: :default, retry: 0

      def perform(tag) = Results.instance << { tag: tag }
    end)

    stub_const("StatusCallback", Class.new do
      def on_complete(*) = Results.instance << { event: :fired }
    end)
  end

  after do
    processor.stop
    ENV.delete("COSMO_JOBS_SCHEDULER_FETCH_TIMEOUT")
    ENV.delete("COSMO_STREAM_EMPTY_BACKOFF_MAX")
  end

  describe ".all" do
    it "lists batches by bid" do
      first = Cosmo::Batch.new
      first.jobs {}
      second = Cosmo::Batch.new
      second.jobs {}

      bids = described_class.all.map(&:bid)
      expect(bids).to include(first.bid, second.bid)
    end
  end

  describe "#stats" do
    it "reports live counts while the batch is still open" do
      batch = Cosmo::Batch.new
      stub_const("SlowStatusJob", Class.new do
        include Cosmo::Job

        options stream: :default, retry: 0

        def perform = sleep(2)
      end)

      batch.jobs { SlowStatusJob.perform_async }

      entry = described_class.new(batch.bid)
      expect(entry.stats).to eq(total: 1, pending: 1, succeeded: 0, failed: 0)
      expect(entry.ready?).to be false
    end

    it "reports final counts once the batch has finalized" do
      batch = Cosmo::Batch.new
      batch.jobs { StatusWorkerJob.perform_async("a") }

      entry = described_class.new(batch.bid)
      wait_until(timeout: 5) { entry.ready? }

      expect(entry.stats).to eq(total: 1, pending: 0, succeeded: 1, failed: 0)
    end
  end

  describe "#meta / #parent_id / #created_at" do
    it "exposes creation metadata" do
      batch = Cosmo::Batch.new
      batch.jobs {}

      entry = described_class.new(batch.bid)
      expect(entry.parent_id).to be_nil
      expect(entry.created_at).to be_within(5).of(Time.now.to_i)
    end

    it "exposes the parent bid for a nested batch" do
      parent = Cosmo::Batch.new
      parent.jobs {}
      child = Cosmo::Batch.new(parent: parent.bid)
      child.jobs {}

      expect(described_class.new(child.bid).parent_id).to eq(parent.bid)
    end
  end

  describe "#callbacks / #callback / #fired?" do
    it "reflects a registered callback before and after it fires" do
      batch = Cosmo::Batch.new
      batch.jobs { StatusWorkerJob.perform_async("a") }
      batch.on(:complete, StatusCallback, marker: "x")

      entry = described_class.new(batch.bid)
      expect(entry.callback(:complete)).to include(class: "StatusCallback", opts: { marker: "x" })
      expect(entry.callbacks[:success]).to be_nil

      wait_until(timeout: 5) { entry.fired?(:complete) }
    end
  end
end
