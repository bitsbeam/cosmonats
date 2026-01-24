# frozen_string_literal: true

RSpec.describe Cosmo::Processor do
  let(:pool) { instance_double(Cosmo::Utils::ThreadPool) }
  let(:running) { Concurrent::AtomicBoolean.new }
  let(:processor) { described_class.new(pool, running) }

  describe ".run" do
    it "creates new instance and runs it" do
      allow_any_instance_of(described_class).to receive(:run)
      result = described_class.run(pool, running)
      expect(result).to be_a(described_class)
    end
  end

  describe "#initialize" do
    it "stores pool and running state" do
      expect(processor.instance_variable_get(:@pool)).to eq(pool)
      expect(processor.instance_variable_get(:@running)).to eq(running)
    end

    it "initializes empty consumers hash" do
      expect(processor.instance_variable_get(:@consumers)).to eq({})
    end
  end

  describe "#run" do
    it "raises NotImplementedError for setup" do
      expect { processor.run }.to raise_error(Cosmo::NotImplementedError)
    end
  end

  describe "#running?" do
    it "returns true when running" do
      running.make_true
      expect(processor.send(:running?)).to be true
    end

    it "returns false when not running" do
      running.make_false
      expect(processor.send(:running?)).to be false
    end
  end

  describe "#fetch_messages" do
    let(:consumer) { double("consumer") }
    let(:messages) { [double("message")] }

    before do
      processor.instance_variable_set(:@consumers, { test: consumer })
    end

    it "fetches messages from consumer" do
      expect(consumer).to receive(:fetch).with(10, timeout: 1).and_return(messages)
      processor.send(:fetch_messages, :test, batch_size: 10, timeout: 1) {}
    end

    it "yields messages when block given" do
      allow(consumer).to receive(:fetch).and_return(messages)
      expect { |b| processor.send(:fetch_messages, :test, batch_size: 10, timeout: 1, &b) }.to yield_with_args(messages)
    end

    it "calls process when no block given" do
      allow(consumer).to receive(:fetch).and_return(messages)
      expect(processor).to receive(:process).with(:test, messages)
      processor.send(:fetch_messages, :test, batch_size: 10, timeout: 1)
    end

    it "handles NATS timeout gracefully" do
      allow(consumer).to receive(:fetch).and_raise(NATS::Timeout)
      expect { processor.send(:fetch_messages, :test, batch_size: 10, timeout: 1) {} }.not_to raise_error
    end
  end

  describe "#client" do
    it "returns Client instance" do
      expect(processor.send(:client)).to be_a(Cosmo::Client)
    end
  end

  describe "#stopwatch" do
    it "returns new Stopwatch instance" do
      expect(processor.send(:stopwatch)).to be_a(Cosmo::Utils::Stopwatch)
    end
  end
end
