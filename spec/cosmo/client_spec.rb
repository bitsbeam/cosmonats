# frozen_string_literal: true

RSpec.describe Cosmo::Client do
  subject(:client) { described_class.new(nats_url: "nats://localhost:4222") }

  let(:stream_name) { "test_stream" }
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
      instance1 = described_class.instance
      instance2 = described_class.instance
      expect(instance1).to be(instance2)
    end
  end

  describe "#initialize" do
    it "connects to NATS server" do
      expect(NATS).to receive(:connect).with("nats://localhost:4222").and_call_original
      instance = described_class.new(nats_url: "nats://localhost:4222")
    ensure
      instance.close
    end

    it "uses NATS_URL from ENV" do
      allow(ENV).to receive(:fetch).with("NATS_URL", "nats://localhost:4222").and_return("nats://example.com:4222")
      expect(NATS).to receive(:connect).with("nats://example.com:4222").and_return(double(:nc, jetstream: nil, close: nil))
      instance = described_class.new
    ensure
      instance.close
    end
  end

  describe "#nc" do
    it "returns NATS client" do
      expect(client.nc).to be_instance_of(NATS::Client)
    end
  end

  describe "#js" do
    it "returns JetStream instance" do
      expect(client.js).to be_instance_of(NATS::JetStream)
    end
  end

  describe "#publish" do
    it "publishes message to subject" do
      client.create_stream(stream_name, { subjects: subjects })

      ack = client.publish(subject_name, "payload")

      message = client.get_message(stream_name, seq: ack.seq)
      expect(message.data).to eq("payload")
    end

    it "raises error if stream doesn't exist" do
      expect { client.publish(subject_name, "payload", stream: "none") }.to raise_error(NATS::JetStream::Error::NoStreamResponse)
    end

    it "raises error if stream exists but subject doesn't" do
      client.create_stream(stream_name, { subjects: subjects })

      expect { client.publish("test.custom_subject", "payload") }.to raise_error(NATS::JetStream::Error::NoStreamResponse)
    end

    it "passes all parameters to jetstream" do
      client.create_stream(stream_name, { subjects: subjects })

      ack = client.publish(subject_name, "payload", header: { "key" => "value" })

      message = client.get_message(stream_name, seq: ack.seq)
      expect(message.headers).to eq({ "key" => "value" })
    end
  end

  describe "#subscribe" do
    let(:config) { { ack_policy: "explicit" } }

    it "creates pull subscription" do
      client.create_stream(stream_name, { subjects: subjects })

      subscription = client.subscribe("test.subject", "consumer", config)

      info = subscription.consumer_info
      expect(info.type).to eq("io.nats.jetstream.api.v1.consumer_info_response")
      expect(info.stream_name).to eq(stream_name)
      expect(info.name).to eq("consumer")
      expect(info.config.ack_policy).to eq("explicit")
      expect(info.num_ack_pending).to eq(0)
      expect(info.num_redelivered).to eq(0)
      expect(info.num_waiting).to eq(0)
      expect(info.num_pending).to eq(0)
    end

    context "without a consumer name" do
      let(:config) { { stream: stream_name, inactive_threshold: 60 } }

      it "creates an ephemeral consumer with a server-assigned name" do
        client.create_stream(stream_name, { subjects: subjects })

        subscription = client.subscribe(subject_name, nil, config)

        info = subscription.consumer_info
        expect(info.stream_name).to eq(stream_name)
        expect(info.name).not_to be_nil
        expect(info.config.durable_name).to be_nil
        expect(info.config.filter_subject).to eq(subject_name)
        expect(info.config.inactive_threshold).to eq(60)
      end

      it "fetches messages published before subscribing" do
        client.create_stream(stream_name, { subjects: subjects })
        client.publish(subject_name, "payload")

        subscription = client.subscribe(subject_name, nil, config)

        messages = subscription.fetch(1, timeout: 2)
        expect(messages.first.data).to eq("payload")
      end

      it "raises without :stream" do
        expect { client.subscribe(subject_name, nil, { inactive_threshold: 60 }) }
          .to raise_error(Cosmo::ArgumentError, /stream/)
      end

      it "raises without :inactive_threshold" do
        expect { client.subscribe(subject_name, nil, { stream: stream_name }) }
          .to raise_error(Cosmo::ArgumentError, /inactive_threshold/)
      end
    end
  end

  describe "#delete_consumer" do
    it "deletes the named consumer" do
      client.create_stream(stream_name, { subjects: subjects })
      client.subscribe("test.subject", "consumer", { ack_policy: "explicit" })

      client.delete_consumer(stream_name, "consumer")

      expect(client.list_consumers(stream_name)).to eq([])
    end
  end

  describe "#stream_info" do
    it "returns stream information" do
      client.create_stream(stream_name, { subjects: subjects })

      result = client.stream_info(stream_name)

      expect(result.type).to eq("io.nats.jetstream.api.v1.stream_info_response")
      expect(result.config).to be_instance_of(NATS::JetStream::API::StreamConfig)
      expect(result.created).to be_instance_of(Time)
      expect(result.state).to be_instance_of(NATS::JetStream::API::StreamState)
      expect(result.domain).to be_nil
    end
  end

  describe "#create_stream" do
    it "creates new stream" do
      client.create_stream(stream_name, { subjects: ["test.>"], max_age: 3600 * Cosmo::Config::NANO })

      result = client.stream_info(stream_name)

      expect(result.config.subjects).to eq(["test.>"])
      expect(result.config.max_age).to eq(3_600_000_000_000)
    end
  end

  describe "#delete_stream" do
    it "deletes stream" do
      client.create_stream(stream_name, { subjects: ["test.>"] })
      expect(client.list_streams.map { _1.dig("config", "name") }).to eq([stream_name])

      client.delete_stream(stream_name)

      expect(client.list_streams).to eq([])
    end
  end

  describe "#list_streams" do
    it "lists streams" do
      expect(client.list_streams).to eq([])

      client.create_stream(stream_name, { subjects: ["test.>"] })

      expect(client.list_streams.map { _1.dig("config", "name") }).to eq([stream_name])
    end

    it "returns [] when NATS times out" do
      allow(client.nc).to receive(:request).and_raise(NATS::IO::Timeout)
      expect(client.list_streams).to eq([])
    end
  end

  describe "#get_message" do
    it "creates new stream" do
      client.create_stream(stream_name, { subjects: ["test.>"] })
      ack = client.publish(subject_name, "payload")

      message = client.get_message(stream_name, seq: ack.seq)

      expect(message.data).to eq("payload")
    end
  end

  describe "#close" do
    it "creates new stream" do
      client.close

      expect { client.stream_info(stream_name) }.to raise_error(NATS::IO::ConnectionClosedError)
    end
  end

  describe "#pause_stream" do
    it "reports paused" do
      client.create_stream(stream_name, { subjects: subjects, storage: "memory" })

      client.pause_stream(stream_name)

      expect(client.stream_paused?(stream_name)).to be true
    end
  end

  describe "#unpause_stream" do
    it "reports not paused" do
      client.create_stream(stream_name, { subjects: subjects, storage: "memory" })
      client.pause_stream(stream_name)
      expect(client.stream_paused?(stream_name)).to be true

      client.unpause_stream(stream_name)

      expect(client.stream_paused?(stream_name)).to be false
    end
  end

  describe "#stream_paused?" do
    it "is not paused initially" do
      client.create_stream(stream_name, { subjects: subjects, storage: "memory" })

      expect(client.stream_paused?(stream_name)).to be false
    end

    it "reports not paused after unpause_stream" do
      client.create_stream(stream_name, { subjects: subjects, storage: "memory" })
      client.pause_stream(stream_name)
      expect(client.stream_paused?(stream_name)).to be true

      client.unpause_stream(stream_name)

      expect(client.stream_paused?(stream_name)).to be false
    end
  end
end
