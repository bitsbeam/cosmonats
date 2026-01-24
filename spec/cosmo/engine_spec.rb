# frozen_string_literal: true

RSpec.describe Cosmo::Engine do
  let(:pool) { instance_double(Cosmo::Utils::ThreadPool) }
  let(:running) { Concurrent::AtomicBoolean.new }

  before do
    allow(Cosmo::Config).to receive(:fetch).with(:concurrency, 1).and_return(2)
    allow(Cosmo::Config).to receive(:[]).with(:timeout).and_return(10)
    allow(Cosmo::Utils::ThreadPool).to receive(:new).and_return(pool)
    allow(pool).to receive(:shutdown)
    allow(pool).to receive(:wait_for_termination)
  end

  describe ".instance" do
    it "returns singleton instance" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe ".run" do
    it "delegates to instance" do
      allow_any_instance_of(described_class).to receive(:run)
      described_class.run("jobs")
    end
  end

  describe "#initialize" do
    it "initializes with concurrency from config" do
      expect(Cosmo::Config).to receive(:fetch).with(:concurrency, 1)
      expect(Cosmo::Utils::ThreadPool).to receive(:new).with(2)
      described_class.new
    end
  end

  describe "#run" do
    let(:engine) { described_class.new }
    let(:signal_handler) { instance_double(Cosmo::Utils::Signal) }
    let(:job_processor) { instance_double(Cosmo::Job::Processor) }
    let(:stream_processor) { instance_double(Cosmo::Stream::Processor) }

    before do
      allow(Cosmo::Utils::Signal).to receive(:trap).and_return(signal_handler)
      allow(signal_handler).to receive(:wait).and_return("INT")
      allow(Cosmo::Job::Processor).to receive(:run).and_return(job_processor)
      allow(Cosmo::Stream::Processor).to receive(:run).and_return(stream_processor)
      allow(engine).to receive(:shutdown)
    end

    it "traps signals" do
      expect(Cosmo::Utils::Signal).to receive(:trap).with(:INT, :TERM)
      expect { engine.run("jobs") }.to output(anything).to_stdout
    end

    it "runs specific processor type" do
      expect(Cosmo::Job::Processor).to receive(:run).with(pool, anything)
      expect { engine.run("jobs") }.to output(anything).to_stdout
    end

    it "runs all processors when type is nil" do
      expect(Cosmo::Job::Processor).to receive(:run)
      expect(Cosmo::Stream::Processor).to receive(:run)
      expect { engine.run(nil) }.to output(anything).to_stdout
    end

    it "waits for signal and shuts down" do
      expect(signal_handler).to receive(:wait)
      expect(engine).to receive(:shutdown)
      expect { engine.run("jobs") }.to output(anything).to_stdout
    end
  end

  describe "#shutdown" do
    let(:engine) { described_class.new }

    it "sets running to false" do
      expect(engine.instance_variable_get(:@running)).to receive(:make_false)
      engine.shutdown
    end

    it "shuts down thread pool" do
      expect(pool).to receive(:shutdown)
      engine.shutdown
    end

    it "waits for termination with timeout" do
      expect(pool).to receive(:wait_for_termination).with(10)
      engine.shutdown
    end
  end
end
