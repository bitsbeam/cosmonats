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

    it "is a subject of its own under the class for a delayed job" do
      data = described_class.new("MyJob", "args", stream: "default", in: 60)

      expect(data.subject).to eq("cosmo.delayed.my_job.#{data.jid}")
    end

    it "keeps the subject option out of a delayed job's own subject" do
      data = described_class.new("MyJob", "args", stream: "default", in: 60, subject: "custom.subject")

      expect(data.subject).to eq("cosmo.delayed.my_job.#{data.jid}")
    end

    it "keeps a namespaced class in one subject token" do
      data = described_class.new("Batches::NurseJob", "args", stream: "default", in: 60)

      expect(data.subject).to eq("cosmo.delayed.batches-nurse_job.#{data.jid}")
    end

    context "with lanes on the stream" do
      before { Cosmo::Config.load(nil, overrides: { consumers: { jobs: { default: { lanes: 4 } } } }) }
      after { Cosmo::Config.load("spec/support/cosmo.yml") }

      it "puts the job on the lane its lane option names" do
        expect(described_class.new("MyJob", "args", stream: "default", lane: 6).subject).to eq("jobs.default.lane-2.my_job")
      end

      it "keeps a batch's jobs on one lane" do
        subjects = Array.new(5) { described_class.new("MyJob", "args", stream: "default", batch_id: "bid123").subject }

        expect(subjects.uniq.size).to eq(1)
        expect(subjects.first).to match(/\Ajobs\.default\.lane-[0-3]\.my_job\z/)
      end

      it "dispatches a delayed job to its lane" do
        data = described_class.new("MyJob", "args", stream: "default", at: 1_700_000_000, lane: 1)

        expect(data.headers).to include("Nats-Schedule-Target" => "jobs.scheduled.my_job", "X-Subject" => "jobs.default.lane-1.my_job")
      end
    end
  end

  describe "#headers" do
    it "carries the jid as the dedup id" do
      expect(data.headers).to eq("Nats-Msg-Id" => data.jid)
    end

    it "makes a delayed job a NATS schedule that fires into the scheduled stream" do
      data = described_class.new("MyJob", "args", stream: "default", at: 1_700_000_000)

      expect(data.headers).to eq("Nats-Msg-Id" => data.jid, "Nats-Schedule" => "@at 2023-11-14T22:13:20Z",
                                 "Nats-Schedule-Target" => "jobs.scheduled.my_job",
                                 "X-Stream" => "default", "X-Subject" => "jobs.default.my_job")
    end

    it "dispatches a delayed job to the subject option" do
      data = described_class.new("MyJob", "args", stream: "default", at: 1_700_000_000, subject: "custom.subject")

      expect(data.headers).to include("X-Stream" => "default", "X-Subject" => "custom.subject")
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
