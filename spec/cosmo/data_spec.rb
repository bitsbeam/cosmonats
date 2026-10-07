# frozen_string_literal: true

RSpec.describe Cosmo::Job::Data do
  let(:data) { described_class.new("MyJob", "args", stream: "default") }

  it "#jid" do
    expect(data.jid).not_to be(nil)
    expect(data.jid.size).to eq(24)
  end

  it "#stream" do
    expect(data.stream).to eq("default")
  end

  describe "#subject" do
    it "derives the subject from the stream and class" do
      expect(data.subject).to eq("jobs.default.my_job")
    end

    it "prefers the subject option" do
      expect(described_class.new("MyJob", "args", stream: "default", subject: "custom.subject").subject).to eq("custom.subject")
    end

    it "targets the scheduled stream for a delayed job" do
      expect(described_class.new("MyJob", "args", stream: "default", in: 60).subject).to eq("jobs.scheduled.my_job")
    end
  end

  describe "#headers" do
    it "carries the jid as the dedup id" do
      expect(data.headers).to eq("Nats-Msg-Id" => data.jid)
    end

    it "tells the scheduler where to dispatch a delayed job" do
      data = described_class.new("MyJob", "args", stream: "default", at: 1_700_000_000)

      expect(data.headers).to eq("Nats-Msg-Id" => data.jid, "X-Execute-At" => 1_700_000_000,
                                 "X-Stream" => "default", "X-Subject" => "jobs.default.my_job")
    end
  end

  describe "#as_json" do
    it "returns defaults" do
      allow(data).to receive(:jid).and_return("jid")

      expect(data.as_json).to eq({ args: "args", class: "MyJob", dead: true, jid: "jid", retry: 3 })
    end

    it "treats retry: false as 0" do
      data = described_class.new("MyJob", "args", stream: "default", retry: false)
      allow(data).to receive(:jid).and_return("jid")

      expect(data.as_json).to eq({ args: "args", class: "MyJob", dead: true, jid: "jid", retry: 0 })
    end

    it "carries the batch_id when given" do
      data = described_class.new("MyJob", "args", stream: "default", batch_id: "bid123")
      allow(data).to receive(:jid).and_return("jid")

      expect(data.as_json).to include(batch_id: "bid123")
    end
  end

  it "#to_json" do
    allow(data).to receive(:jid).and_return("jid")

    expect(data.to_json).to eq(%({"jid":"jid","class":"MyJob","args":"args","retry":3,"dead":true}))
  end
end
