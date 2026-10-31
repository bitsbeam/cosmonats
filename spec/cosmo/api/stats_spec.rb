# frozen_string_literal: true

RSpec.describe Cosmo::API::Stats do
  let(:counter) { instance_double(Cosmo::API::Stats::Totals, processed: 42, failed: 3) }
  let(:jobs) { instance_double(Cosmo::API::Stats::Jobs) }
  let(:running) do
    [{ jid: "b", worker: "web-1", stream: "low", started_at: 10 }, { jid: "a", worker: "web-1", stream: "default", started_at: 20 },
     { jid: "c", worker: "web-2", stream: "default", started_at: 30 }]
  end

  before do
    allow(Cosmo::API::Stats::Totals).to receive(:instance).and_return(counter)
    allow(Cosmo::API::Stats::Jobs).to receive(:instance).and_return(jobs)
    allow(jobs).to receive(:sample) { |limit| running.first(limit) }
    allow(jobs).to receive(:longest) { |page:, limit:| running.sort_by { -_1[:started_at] }.slice((page - 1) * limit, limit) }
    allow(jobs).to receive(:list) { |page:, limit:| running.slice((page - 1) * limit, limit) }
    allow(jobs).to receive(:count) { |stream| stream ? running.count { _1[:stream] == stream } : running.size }
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
    it "counts the running jobs without reading them" do
      expect(described_class.busy).to eq(3)
    end
  end

  describe ".running" do
    it "samples up to the limit of the running jobs, with the worker running each" do
      expect(described_class.running(2).map { _1.values_at(:jid, :worker) }).to eq([%w[b web-1], %w[a web-1]])
    end
  end

  describe ".running_page" do
    it "reads one page of the running jobs" do
      expect(described_class.running_page(page: 2, limit: 2).map { _1[:jid] }).to eq(%w[c])
    end

    it "reads the longest running first on request" do
      expect(described_class.running_page(page: 1, limit: 2, longest: true).map { _1[:jid] }).to eq(%w[c a])
    end
  end

  describe ".busy_streams" do
    it "counts the running jobs of each job stream" do
      allow(Cosmo::API::Stream).to receive(:jobs).and_return([double(name: "default"), double(name: "low"), double(name: "idle")])
      expect(described_class.busy_streams).to eq("default" => 2, "low" => 1, "idle" => 0)
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
      expect(described_class.queue(stream)).to include(busy: 2)
    end
  end

  describe ".queues" do
    it "describes every job stream, counting running jobs once" do
      streams = [double(name: "default", size: 1, retries: 0, paused?: false),
                 double(name: "low", size: 0, retries: 5, paused?: false)]
      allow(Cosmo::API::Stream).to receive(:jobs).and_return(streams)

      expect(described_class.queues).to eq([
                                             { name: "default", size: 1, busy: 2, retries: 0, paused: false },
                                             { name: "low", size: 0, busy: 1, retries: 5, paused: false }
                                           ])
      expect(Cosmo::API::Stream).to have_received(:jobs).once
    end
  end

  describe ".summary" do
    it "returns all counters as a hash" do
      summary = described_class.summary
      expect(summary).to include(:processed, :failed, :busy, :enqueued, :retries, :scheduled, :dead)
      expect(summary[:processed]).to eq(42)
      expect(summary[:failed]).to eq(3)
      expect(summary[:busy]).to eq(3)
    end

    it "lists the job streams once" do
      described_class.summary
      expect(Cosmo::API::Stream).to have_received(:jobs).once
    end
  end
end
