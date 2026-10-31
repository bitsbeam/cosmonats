# frozen_string_literal: true

RSpec.describe Cosmo::API::Stats::Jobs do
  subject(:jobs) { described_class.new }

  let(:job) { ->(jid, stream = "default", started_at = 1) { { jid:, class: "MyJob", stream:, started_at: } } }

  before { jobs.instance_variable_get(:@kv).clean rescue nil }
  after { jobs.instance_variable_get(:@kv).clean rescue nil }

  describe "#report" do
    it "stores each job under its stream and worker, so the server can count them" do
      jobs.report("web-1", [job.call("a"), job.call("b", "low")])
      jobs.report("web-2", [job.call("c")])

      expect([jobs.count, jobs.count("default"), jobs.count("low"), jobs.count("none")]).to eq([3, 2, 1, 0])
    end

    it "lets a job no longer reported expire, without deleting it" do
      stub_const("#{described_class}::ENTRY_TTL", 1)
      jobs.report("web-1", [job.call("a"), job.call("b")])
      jobs.report("web-1", [job.call("b")])
      expect(jobs.count).to eq(2)

      wait_until(timeout: 5) { jobs.count < 1 }
    end

    it "doesn't double count a job reported on every beat" do
      3.times { jobs.report("web-1", [job.call("a")]) }
      expect(jobs.count).to eq(1)
    end

    it "accepts identities and ids with characters a subject cannot hold" do
      jobs.report("web 1.local:42", [job.call("a b.c")])
      expect(jobs.count("default")).to eq(1)
    end

    it "recreates the bucket when it was deleted under a running worker" do
      jobs.report("web-1", [job.call("a")])
      client.delete_stream("KV_#{described_class::BUCKET}")

      jobs.report("web-1", [job.call("a")])
      expect(jobs.count).to eq(1)
    end
  end

  describe "#clear" do
    it "removes only the jobs of one worker" do
      jobs.report("web-1", [job.call("a"), job.call("b")])
      jobs.report("web-2", [job.call("c")])

      jobs.clear("web-1")
      expect(jobs.all.map { _1[:jid] }).to eq(["c"])
    end
  end

  describe "#sample" do
    before { jobs.report("web-1", Array.new(5) { |i| job.call("j#{i}") }) }

    it "reads at most the limit of the running jobs" do
      expect(jobs.sample(3).size).to eq(3)
      expect(jobs.sample(10).size).to eq(5)
    end

    it "reads nothing while no job runs" do
      jobs.clear("web-1")
      expect(jobs.sample(3)).to eq([])
    end
  end

  describe "#longest" do
    before { jobs.report("web-1", [job.call("late", "default", 30), job.call("early", "low", 10), job.call("mid", "default", 20)]) }

    it "pages every running job longest running first, then serves the same read until the next heartbeat" do
      expect(jobs.longest(page: 1, limit: 2).map { _1[:jid] }).to eq(%w[early mid])
      expect(jobs.longest(page: 2, limit: 2).map { _1[:jid] }).to eq(%w[late])

      jobs.clear("web-1")
      expect(jobs.longest(limit: 5).size).to eq(3)
    end

    it "reads again once its ttl has passed" do
      jobs.longest
      jobs.clear("web-1")

      stub_const("Cosmo::API::Stats::Jobs::LONGEST_TTL", 0)
      expect(jobs.longest).to eq([])
    end

    it "shares one read between concurrent callers" do
      allow(jobs).to receive(:all).and_call_original

      Array.new(5) { Thread.new { jobs.longest } }.each(&:join)
      expect(jobs).to have_received(:all).once
    end
  end

  describe "#list" do
    before do
      stub_const("Cosmo::API::Stats::Jobs::KEYS_TTL", 0)
      jobs.report("web-2", [job.call("c", "default")])
      jobs.report("web-1", [job.call("b", "low"), job.call("a", "default")])
    end

    it "pages the jobs in stream, worker and id order, however often they are rewritten" do
      jobs.report("web-1", [job.call("b", "low"), job.call("a", "default")])

      pages = (1..2).map { |page| jobs.list(page:, limit: 2).map { _1[:jid] } }
      expect(pages).to eq([%w[a c], %w[b]])
    end

    it "counts them without reading them" do
      expect(jobs.size).to eq(3)
    end
  end
end
