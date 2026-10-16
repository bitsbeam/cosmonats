# frozen_string_literal: true

RSpec.describe Cosmo::API::Stats do
  let(:counter) { instance_double(Cosmo::API::Stats::Totals, processed: 42, failed: 3) }
  let(:busy) { instance_double(Cosmo::API::Stats::Busy, size: 2) }

  before do
    allow(Cosmo::API::Stats::Totals).to receive(:instance).and_return(counter)
    allow(Cosmo::API::Stats::Busy).to receive(:instance).and_return(busy)
    allow(Cosmo::API::Stream).to receive(:jobs).and_return([])
    allow(Cosmo::API::Stream).to receive(:new).with("scheduled").and_return(double(size: 5))
    allow(Cosmo::API::Stream).to receive(:new).with("dead").and_return(double(size: 1))
  end

  describe ".processed" do
    it "returns processed count from counter" do
      expect(described_class.processed).to eq(42)
    end
  end

  describe ".failed" do
    it "returns failed count from counter" do
      expect(described_class.failed).to eq(3)
    end
  end

  describe ".busy" do
    it "returns busy size" do
      expect(described_class.busy).to eq(2)
    end
  end

  describe ".enqueued" do
    it "returns sum of job stream sizes" do
      stream1 = double(size: 10, retries: 0)
      stream2 = double(size: 5, retries: 0)
      allow(Cosmo::API::Stream).to receive(:jobs).and_return([stream1, stream2])
      expect(described_class.enqueued).to eq(15)
    end
  end

  describe ".retries" do
    it "returns sum of retries across job streams" do
      stream1 = double(size: 0, retries: 4)
      stream2 = double(size: 0, retries: 2)
      allow(Cosmo::API::Stream).to receive(:jobs).and_return([stream1, stream2])
      expect(described_class.retries).to eq(6)
    end
  end

  describe ".scheduled" do
    it "returns scheduled stream size" do
      expect(described_class.scheduled).to eq(5)
    end
  end

  describe ".dead" do
    it "returns dead stream size" do
      expect(described_class.dead).to eq(1)
    end
  end

  describe ".queue" do
    let(:stream) { double(name: "default", size: 7, retries: 2, paused?: true) }

    it "describes a job stream with its running jobs" do
      expect(described_class.queue(stream, { "default" => 3, "low" => 1 }))
        .to eq(name: "default", size: 7, busy: 3, retries: 2, paused: true)
    end

    it "counts no running jobs for a stream without any" do
      expect(described_class.queue(stream, { "low" => 1 })).to include(busy: 0)
    end

    it "counts running jobs itself without a tally" do
      allow(busy).to receive(:by_stream).and_return({ "default" => 4 })

      expect(described_class.queue(stream)).to include(busy: 4)
    end
  end

  describe ".queues" do
    it "describes every job stream, counting running jobs once" do
      streams = [double(name: "default", size: 1, retries: 0, paused?: false),
                 double(name: "low", size: 0, retries: 5, paused?: false)]
      allow(Cosmo::API::Stream).to receive(:jobs).and_return(streams)
      allow(busy).to receive(:by_stream).once.and_return({ "low" => 2 })

      expect(described_class.queues).to eq([
                                             { name: "default", size: 1, busy: 0, retries: 0, paused: false },
                                             { name: "low", size: 0, busy: 2, retries: 5, paused: false }
                                           ])
    end
  end

  describe ".summary" do
    it "returns all counters as a hash" do
      summary = described_class.summary
      expect(summary).to include(:processed, :failed, :busy, :enqueued, :retries, :scheduled, :dead)
      expect(summary[:processed]).to eq(42)
      expect(summary[:failed]).to eq(3)
      expect(summary[:busy]).to eq(2)
    end

    it "lists the job streams once" do
      described_class.summary
      expect(Cosmo::API::Stream).to have_received(:jobs).once
    end
  end
end
