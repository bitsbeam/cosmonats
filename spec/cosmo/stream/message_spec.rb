# frozen_string_literal: true

RSpec.describe Cosmo::Stream::Message do
  let(:msg) { double("nats_message") }
  let(:metadata) { double("metadata", sequence: sequence, num_delivered: 1, num_pending: 10, timestamp: Time.now) }
  let(:sequence) { double("sequence", stream: 100, consumer: 50) }
  let(:message) { described_class.new(msg) }

  before do
    allow(msg).to receive(:subject).and_return("test.subject")
    allow(msg).to receive(:reply).and_return("reply.subject")
    allow(msg).to receive(:header).and_return({})
    allow(msg).to receive(:metadata).and_return(metadata)
    allow(msg).to receive(:data).and_return('{"key":"value"}')
    allow(msg).to receive(:ack)
    allow(msg).to receive(:nack)
    allow(msg).to receive(:term)
    allow(msg).to receive(:in_progress)
  end

  describe "#initialize" do
    it "stores NATS message" do
      expect(message.instance_variable_get(:@msg)).to eq(msg)
    end

    it "uses default serializer" do
      expect(message.instance_variable_get(:@serializer)).to eq(Cosmo::Stream::Serializer)
    end

    it "accepts custom serializer" do
      custom_serializer = double("serializer")
      msg = described_class.new(msg, serializer: custom_serializer)
      expect(msg.instance_variable_get(:@serializer)).to eq(custom_serializer)
    end
  end

  describe "#data" do
    it "deserializes message data" do
      expect(Cosmo::Stream::Serializer).to receive(:deserialize).with('{"key":"value"}')
      message.data
    end

    it "uses custom serializer for deserialization" do
      custom_serializer = double("serializer")
      expect(custom_serializer).to receive(:deserialize).with('{"key":"value"}')
      message = described_class.new(msg, serializer: custom_serializer)
      message.data
    end
  end

  describe "delegated methods" do
    it "delegates subject" do
      expect(message.subject).to eq("test.subject")
    end

    it "delegates reply" do
      expect(message.reply).to eq("reply.subject")
    end

    it "delegates header" do
      expect(message.header).to eq({})
    end

    it "delegates metadata" do
      expect(message.metadata).to eq(metadata)
    end

    it "delegates ack" do
      expect(msg).to receive(:ack)
      message.ack
    end

    it "delegates nack" do
      expect(msg).to receive(:nack)
      message.nack
    end

    it "delegates term" do
      expect(msg).to receive(:term)
      message.term
    end

    it "delegates in_progress" do
      expect(msg).to receive(:in_progress)
      message.in_progress
    end

    it "delegates timestamp" do
      expect(message.timestamp).to eq(metadata.timestamp)
    end

    it "delegates num_delivered" do
      expect(message.num_delivered).to eq(1)
    end

    it "delegates num_pending" do
      expect(message.num_pending).to eq(10)
    end
  end

  describe "#stream_sequence" do
    it "returns stream sequence number" do
      expect(message.stream_sequence).to eq(100)
    end
  end

  describe "#consumer_sequence" do
    it "returns consumer sequence number" do
      expect(message.consumer_sequence).to eq(50)
    end
  end
end
