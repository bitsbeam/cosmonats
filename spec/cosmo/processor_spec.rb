# frozen_string_literal: true

RSpec.describe Cosmo::Processor do
  let(:pool) { instance_double(Cosmo::Utils::ThreadPool) }
  let(:running) { Concurrent::AtomicBoolean.new }
  let(:quiet) { Concurrent::AtomicBoolean.new }
  let(:options) { {} }
  let(:processor) { described_class.new(pool, running, options, quiet: quiet) }

  describe ".run" do
    it "creates new instance and runs it" do
      allow_any_instance_of(described_class).to receive(:run)
      result = described_class.run(pool, running, options, quiet: quiet)
      expect(result).to be_a(described_class)
    end
  end

  describe "#initialize" do
    it "stores pool and running state" do
      expect(processor.instance_variable_get(:@pool)).to eq(pool)
      expect(processor.instance_variable_get(:@running)).to eq(running)
    end

    it "initializes empty consumers array" do
      expect(processor.instance_variable_get(:@consumers)).to eq([])
    end

    it "stores options" do
      expect(processor.instance_variable_get(:@options)).to eq(options)
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

  describe "#quiet?" do
    it "returns false when not quiet" do
      expect(processor.send(:quiet?)).to be false
    end

    it "returns true once the injected quiet flag is set" do
      quiet.make_true
      expect(processor.send(:quiet?)).to be true
    end
  end

  describe "#work_loop" do
    let(:pool) { Cosmo::Utils::ThreadPool.new(3) }
    let(:subscription) { double("subscription") }
    let(:fetches) { Concurrent::AtomicFixnum.new }

    before do
      allow(Cosmo::API::Stream).to receive(:new).and_return(instance_double(Cosmo::API::Stream, paused?: false))
      allow(processor).to receive_messages(
        consumers: [[subscription, { stream: :default, batch_size: 1 }, nil]], fetch_timeout: 0.1, fetch_subjects: "jobs.default.>"
      )
      allow(processor).to receive(:fetch) do
        fetches.increment
        sleep 0.05
        nil
      end
    end

    after { pool.shutdown }

    it "backs off once per round of parallel empty fetches" do
      running.make_true
      loop_thread = Thread.new { processor.send(:work_loop) }
      sleep 0.2
      running.make_false
      loop_thread.join(1)
      pool.wait_idle

      expect(fetches.value).to be >= 3
      expect(processor.send(:consumer_state)["default"].first).to eq(fetches.value / 3)
    end

    it "counts threads processing messages as busy, but not threads waiting on a fetch" do
      release = Concurrent::Event.new
      delivered = Concurrent::AtomicBoolean.new
      allow(processor).to receive(:fetch) do
        sleep 0.05
        [double("message")] if delivered.make_true
      end
      allow(processor).to receive(:process) { release.wait(2) }

      running.make_true
      loop_thread = Thread.new { processor.send(:work_loop) }
      wait_until(timeout: 2) { processor.busy == 1 }
      sleep 0.1
      expect(processor.busy).to eq(1)

      release.set
      wait_until(timeout: 2) { processor.busy.zero? }
    ensure
      running.make_false
      loop_thread&.join(1)
    end
  end

  describe "#fetch_messages" do
    let(:subscription) { double("subscription") }
    let(:messages) { [double("message")] }

    it "fetches messages from subscription" do
      expect(subscription).to receive(:fetch).with(10, timeout: 1).and_return(messages)
      processor.send(:fetch, subscription, batch_size: 10, timeout: 1)
    end

    it "handles NATS timeout gracefully" do
      allow(subscription).to receive(:fetch).and_raise(NATS::Timeout)
      expect { processor.send(:fetch, subscription, batch_size: 10, timeout: 1) }.not_to raise_error
    end

    it "handles StandardError by logging and sleeping with backoff" do
      error = StandardError.new("connection error")
      allow(subscription).to receive(:fetch).and_raise(error)
      allow(ENV).to receive(:fetch).with("COSMO_STREAMS_FETCH_BACKOFF", 5).and_return("3")

      expect(Cosmo::Logger).to receive(:error).with("Snap! Error just happened")
      expect(Cosmo::Logger).to receive(:error).with(start_with("StandardError: connection error"))
      expect(processor).to receive(:sleep).with(3.0)

      processor.send(:fetch, subscription, batch_size: 10, timeout: 1)
    end

    it "sleeps with timeout if backoff is smaller" do
      error = StandardError.new("test error")
      allow(subscription).to receive(:fetch).and_raise(error)
      allow(ENV).to receive(:fetch).with("COSMO_STREAMS_FETCH_BACKOFF", 5).and_return("1")
      allow(Cosmo::Logger).to receive(:error)

      expect(processor).to receive(:sleep).with(10.0)

      processor.send(:fetch, subscription, batch_size: 10, timeout: 10)
    end

    it "uses default backoff when env var not set" do
      error = StandardError.new("test error")
      allow(subscription).to receive(:fetch).and_raise(error)
      allow(Cosmo::Logger).to receive(:error)

      expect(processor).to receive(:sleep).with(5.0)

      processor.send(:fetch, subscription, batch_size: 10, timeout: 1)
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
