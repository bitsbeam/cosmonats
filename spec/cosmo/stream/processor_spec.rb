# frozen_string_literal: true

RSpec.describe Cosmo::Stream::Processor do
  let(:pool) { instance_double(Cosmo::Utils::ThreadPool) }
  let(:running) { Concurrent::AtomicBoolean.new }
  let(:processor) { described_class.new(pool, running) }
  let(:client) { instance_double(Cosmo::Client) }

  before do
    allow(Cosmo::Client).to receive(:instance).and_return(client)
    allow(Cosmo::Config).to receive(:dig).with(:consumers, :streams).and_return(nil)
    allow(Cosmo::Config.system).to receive(:[]).with(:streams).and_return([])
    running.make_true
  end

  describe "#initialize" do
    it "inherits from Processor" do
      expect(processor).to be_a(Cosmo::Processor)
    end
  end

  describe "#setup (private)" do
    it "calls setup methods in order" do
      expect(processor).to receive(:setup_configs).ordered
      expect(processor).to receive(:setup_processors).ordered
      expect(processor).to receive(:setup_consumers).ordered
      processor.send(:setup)
    end
  end

  describe "#work_loop (private)" do
    before do
      processor.instance_variable_set(:@consumers, { test_stream: double("consumer") })
      processor.instance_variable_set(:@configs, { test_stream: { batch_size: 10 } })
      allow(pool).to receive(:post).and_yield
      allow(processor).to receive(:fetch_messages)
    end

    it "fetches messages for each stream" do
      running.make_false
      thread = Thread.new { processor.send(:work_loop) }
      sleep 0.1
      thread.kill
    end

    it "handles RejectedExecutionError during shutdown" do
      allow(pool).to receive(:post).and_raise(Concurrent::RejectedExecutionError)
      running.make_false
      expect { processor.send(:work_loop) }.not_to raise_error
    end
  end

  describe "#process (private)" do
    let(:nats_message) { double("nats_message") }
    let(:metadata) { double("metadata", sequence: sequence, num_delivered: 1, num_pending: 5, timestamp: Time.now) }
    let(:sequence) { double("sequence", stream: 100, consumer: 50) }
    let(:stream_processor) { double("stream_processor", class: stream_class) }
    let(:stream_class) { double("stream_class", default_options: { publisher: { serializer: nil } }) }

    before do
      allow(nats_message).to receive(:metadata).and_return(metadata)
      allow(nats_message).to receive(:data).and_return('{"key":"value"}')
      processor.instance_variable_set(:@processors, { test_stream: stream_processor })
      allow(stream_processor).to receive(:process)
      allow(Cosmo::Logger).to receive(:with).and_yield
      allow(Cosmo::Logger).to receive(:info)
      allow(Cosmo::Logger).to receive(:debug)
    end

    it "processes messages with stream processor" do
      expect(stream_processor).to receive(:process)
      processor.send(:process, :test_stream, [nats_message])
    end

    it "wraps messages in Stream::Message objects" do
      expect(stream_processor).to receive(:process) do |messages|
        expect(messages.first).to be_a(Cosmo::Stream::Message)
      end
      processor.send(:process, :test_stream, [nats_message])
    end

    it "logs processing with metadata" do
      expect(Cosmo::Logger).to receive(:with).with(hash_including(
                                                     seq_stream: 100,
                                                     seq_consumer: 50,
                                                     num_pending: 5
                                                   ))
      processor.send(:process, :test_stream, [nats_message])
    end

    it "handles StandardError gracefully" do
      allow(stream_processor).to receive(:process).and_raise(StandardError, "Processing failed")
      expect(Cosmo::Logger).to receive(:debug).with(kind_of(StandardError))
      expect { processor.send(:process, :test_stream, [nats_message]) }.not_to raise_error
    end
  end

  describe "#setup_configs (private)" do
    let(:stream_class) do
      Class.new do
        include Cosmo::Stream

        def process_one; end
      end
    end

    before do
      stub_const("TestStreamClass", stream_class)
      allow(Cosmo::Config).to receive(:dig).with(:consumers, :streams).and_return([
                                                                                    { stream: "configured_stream", class: "TestStreamClass" }
                                                                                  ])
      allow(Cosmo::Config.system).to receive(:[]).with(:streams).and_return([stream_class])
    end

    it "merges config from Config and system streams" do
      processor.send(:setup_configs)
      configs = processor.instance_variable_get(:@configs)
      expect(configs).to have_key(:configured_stream)
    end

    it "skips invalid class names" do
      allow(Cosmo::Config).to receive(:dig).with(:consumers, :streams).and_return([
                                                                                    { stream: "invalid", class: "NonExistentClass" }
                                                                                  ])
      expect { processor.send(:setup_configs) }.not_to raise_error
    end
  end

  describe "#setup_processors (private)" do
    let(:stream_class) do
      Class.new do
        attr_accessor :initialized

        def initialize
          @initialized = true
        end
      end
    end

    before do
      processor.instance_variable_set(:@configs, { test: { class: stream_class } })
    end

    it "instantiates processor for each stream" do
      processor.send(:setup_processors)
      processors = processor.instance_variable_get(:@processors)
      expect(processors[:test]).to be_a(stream_class)
      expect(processors[:test].initialized).to be true
    end
  end

  describe "#setup_consumers (private)" do
    let(:consumer) { double("consumer") }
    let(:deliver_policy) { { deliver_policy: "all" } }

    before do
      processor.instance_variable_set(:@configs, {
                                        test_stream: {
                                          stream_name: :test_stream,
                                          consumer_name: "consumer-test",
                                          consumer: { ack_policy: "explicit", subjects: ["test.>"] },
                                          start_position: nil
                                        }
                                      })
      allow(Cosmo::Config).to receive(:deliver_policy).and_return(deliver_policy)
      allow(client).to receive(:subscribe).and_return(consumer)
    end

    it "creates consumer for each stream" do
      expect(client).to receive(:subscribe).with(
        ["test.>"],
        "consumer-test",
        hash_including(ack_policy: "explicit", deliver_policy: "all")
      )
      processor.send(:setup_consumers)
    end

    it "stores consumers by stream name" do
      processor.send(:setup_consumers)
      consumers = processor.instance_variable_get(:@consumers)
      expect(consumers[:test_stream]).to eq(consumer)
    end
  end
end
