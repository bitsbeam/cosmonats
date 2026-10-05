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

  describe ".summary" do
    it "returns all counters as a hash" do
      summary = described_class.summary
      expect(summary).to include(:processed, :failed, :busy, :enqueued, :retries, :scheduled, :dead)
      expect(summary[:processed]).to eq(42)
      expect(summary[:failed]).to eq(3)
      expect(summary[:busy]).to eq(2)
    end
  end
end
