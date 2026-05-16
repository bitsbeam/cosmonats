# frozen_string_literal: true

RSpec.describe Cosmo::API::Stream do
  let(:stream_name) { "teststreamapi" }
  let(:subject_pattern) { "teststreamapi.>" }
  let(:payload) { Cosmo::Utils::Json.dump({ class: "MyWorker", args: [], jid: "abc" }) }

  before do
    destroy_streams
    client.create_stream(stream_name, { subjects: [subject_pattern], allow_direct: true, storage: "memory" })
  end

  after { destroy_streams }

  describe ".all" do
    it "returns all streams" do
      streams = described_class.all
      expect(streams.map(&:name)).to include(stream_name)
    end
  end

  describe ".jobs" do
    it "returns only configured job streams" do
      allow(Cosmo::Config).to receive(:[]).with(:setup).and_return({ jobs: { default: {}, scheduled: {}, dead: {} } })
      streams = described_class.jobs
      expect(streams).to be_an(Array)
    end
  end

  describe "#info" do
    subject(:stream) { described_class.new(stream_name) }

    it "returns stream state and config" do
      info = stream.info
      expect(info).to have_key(:state)
      expect(info).to have_key(:config)
    end
  end

  describe "#total / #size" do
    subject(:stream) { described_class.new(stream_name) }

    it "returns 0 for empty stream" do
      expect(stream.total).to eq(0)
    end

    it "counts messages" do
      client.publish("teststreamapi.job", payload)
      expect(stream.total).to eq(1)
    end

    it "is aliased as #size" do
      expect(stream.size).to eq(stream.total)
    end
  end

  describe "#message" do
    subject(:stream) { described_class.new(stream_name) }

    it "fetches a message by seq" do
      ack = client.publish("teststreamapi.job", payload)
      msg = stream.message(ack.seq)
      expect(msg).to be_a(Cosmo::API::Job)
      expect(msg.seq.to_i).to eq(ack.seq)
    end

    it "returns nil for non-existent seq" do
      expect(stream.message(9999)).to be_nil
    end
  end

  describe "#messages" do
    subject(:stream) { described_class.new(stream_name) }

    before do
      3.times { |i| client.publish("teststreamapi.job", Cosmo::Utils::Json.dump({ class: "W", args: [i], jid: "j#{i}" })) }
    end

    it "returns messages as Job objects" do
      msgs = stream.messages
      expect(msgs).to all(be_a(Cosmo::API::Job))
    end

    it "respects limit" do
      expect(stream.messages(limit: 2).size).to eq(2)
    end
  end

  describe "#each" do
    subject(:stream) { described_class.new(stream_name) }

    before do
      2.times { |i| client.publish("teststreamapi.job", Cosmo::Utils::Json.dump({ class: "W", args: [i], jid: "j#{i}" })) }
    end

    it "yields each job" do
      jobs = stream.map { |j| j }
      expect(jobs.size).to eq(2)
      expect(jobs).to all(be_a(Cosmo::API::Job))
    end
  end

  describe "#delete" do
    subject(:stream) { described_class.new(stream_name) }

    it "deletes a message by seq" do
      ack = client.publish("teststreamapi.job", payload)
      stream.delete(ack.seq)
      expect(stream.message(ack.seq)).to be_nil
    end
  end

  describe "#pause!" do
    subject(:stream) { described_class.new(stream_name) }

    it "pauses stream" do
      stream.pause!

      expect(stream.paused?).to be true
    end
  end

  describe "#unpause!" do
    subject(:stream) { described_class.new(stream_name) }

    it "resumes stream" do
      stream.pause!
      expect(stream.paused?).to be true

      stream.unpause!

      expect(stream.paused?).to be false
    end
  end

  describe "#paused?" do
    subject(:stream) { described_class.new(stream_name) }

    it "is not paused initially" do
      expect(stream.paused?).to be false
    end

    it "returns false for a freshly created stream" do
      client.create_stream("empty-stream-test", { subjects: ["empty.>"], storage: "memory" })
      expect(described_class.new("empty-stream-test").paused?).to be false
    end

    it "persists pause state" do
      stream.pause!

      expect(described_class.new(stream_name).paused?).to be true
    end
  end
end
