# frozen_string_literal: true

RSpec.describe Cosmo::Publisher do
  let(:client) { Cosmo::Client.new }
  let(:publisher) { described_class.new }
  let(:stream_name) { :test }
  let(:subject_name) { "test.subject" }
  let(:subjects) { [subject_name] }

  before { destroy_streams }
  after do
    destroy_streams
    client.close
  rescue NATS::IO::ConnectionClosedError
    # nop
  end

  describe ".instance" do
    it "returns singleton instance" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe ".publish" do
    it "delegates publish to instance" do
      expect_any_instance_of(described_class).to receive(:publish).with("subject", { data: "test" })
      described_class.publish("subject", { data: "test" })
    end
  end

  describe "#initialize" do
    it "initializes with client instance" do
      expect(Cosmo::Client).to receive(:instance)
      described_class.new
    end
  end

  describe "#publish" do
    let(:data) { { key: "value" } }

    before { client.create_stream(stream_name, subjects: subjects) }

    it "serializes and publishes data" do
      ack = publisher.publish(subject_name, data)

      message = client.get_message(stream_name, seq: ack.seq)
      expect(message.data).to eq('{"key":"value"}')
    end

    it "uses custom serializer when provided" do
      custom_serializer = double("serializer")
      expect(custom_serializer).to receive(:serialize).with(data).and_return("custom")

      ack = publisher.publish(subject_name, data, serializer: custom_serializer)

      message = client.get_message(stream_name, seq: ack.seq)
      expect(message.data).to eq("custom")
    end

    it "passes additional options to client" do
      ack = publisher.publish(subject_name, data, header: { "key" => "value" })

      message = client.get_message(stream_name, seq: ack.seq)
      expect(message.headers).to eq({ "key" => "value" })
    end
  end
end
