# frozen_string_literal: true

RSpec.describe Cosmo::Publisher do
  let(:client) { Cosmo::Client.new }
  let(:publisher) { described_class.new }
  let(:stream_name) { :test }
  let(:subject_name) { "test.subject" }
  let(:subjects) { [subject_name] }

  before { clean_streams }
  after do
    clean_streams
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

  describe ".publish_job" do
    it "delegates publish_job to instance" do
      job_data = instance_double(Cosmo::Job::Data)
      expect_any_instance_of(described_class).to receive(:publish_job).with(job_data)
      described_class.publish_job(job_data)
    end
  end

  describe ".publish_batch" do
    it "delegates publish_batch to instance" do
      batch = [{ key: "value" }]
      expect_any_instance_of(described_class).to receive(:publish_batch).with("subject", batch)
      described_class.publish_batch("subject", batch)
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

      message = client.get_message(stream_name, ack.seq)
      expect(message.data).to eq('{"key":"value"}')
    end

    it "uses custom serializer when provided" do
      custom_serializer = double("serializer")
      expect(custom_serializer).to receive(:serialize).with(data).and_return("custom")

      ack = publisher.publish(subject_name, data, serializer: custom_serializer)

      message = client.get_message(stream_name, ack.seq)
      expect(message.data).to eq("custom")
    end

    it "passes additional options to client" do
      ack = publisher.publish(subject_name, data, header: { "key" => "value" })

      message = client.get_message(stream_name, ack.seq)
      expect(message.headers).to eq({"key" => "value"})
    end
  end

  describe "#publish_job" do
    let(:job_data) { instance_double(Cosmo::Job::Data, jid: "job123") }

    before { client.create_stream(stream_name, subjects: subjects) }

    it "publishes job data" do
      allow(job_data).to receive(:to_args).and_return([subject_name, "payload", { stream: stream_name }])
      result = publisher.publish_job(job_data)
      expect(result).to eq("job123")
    end

    it "raises StreamNotFoundError when stream not found" do
      allow(job_data).to receive(:to_args).and_return(["subject", "payload", { stream: "missing" }])
      expect { publisher.publish_job(job_data) }.to raise_error(Cosmo::StreamNotFoundError, "Missing stream `missing`")
    end
  end

  describe "#publish_batch" do
    let(:batch) { [{ key: "value1" }, { key: "value2" }] }

    it "publishes each item in batch" do
      expect(publisher).to receive(:publish).with("test.subject", { key: "value1" })
      expect(publisher).to receive(:publish).with("test.subject", { key: "value2" })
      publisher.publish_batch("test.subject", batch)
    end

    it "passes options to each publish call" do
      expect(publisher).to receive(:publish).with("test.subject", { key: "value1" }, stream: "test")
      expect(publisher).to receive(:publish).with("test.subject", { key: "value2" }, stream: "test")
      publisher.publish_batch("test.subject", batch, stream: "test")
    end
  end
end
