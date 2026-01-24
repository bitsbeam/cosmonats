# frozen_string_literal: true

RSpec.describe Cosmo::Utils::ThreadPool do
  let(:concurrency) { 2 }
  let(:timeout) { 1 }
  let(:pool) { described_class.new(concurrency) }

  after do
    pool.shutdown
    pool.wait_for_termination(1)
  end

  describe "#initialize" do
    it "creates fixed thread pool with specified concurrency" do
      allow(Concurrent::FixedThreadPool).to receive(:new).and_call_original

      pool

      expect(Concurrent::FixedThreadPool).to have_received(:new).with(concurrency)
    end
  end

  describe "#post" do
    it "executes block in thread pool" do
      result = Concurrent::IVar.new
      pool.post do
        sleep 0.1
        result.set("executed")
      end
      expect(result.value(timeout)).to eq("executed")
    end

    it "blocks when no threads available" do
      pool.post { sleep 0.5 }
      pool.post { sleep 0.5 }

      blocked = nil
      thread = Thread.new do
        blocked = true
        pool.post { blocked = :working }
        blocked = false
      end

      sleep 0.1
      expect(blocked).to be true
      thread.join
      expect(blocked).to be false
    end

    it "handles errors without crashing pool" do
      pool.post { raise StandardError, "Task error" }
      sleep 0.1

      result = nil
      pool.post { result = "next task" }
      sleep 0.1
      expect(result).to eq("next task")
    end
  end

  describe "#shutdown" do
    it "delegates to underlying pool" do
      test_pool = described_class.new(concurrency)
      concurrent_pool = test_pool.instance_variable_get(:@pool)
      allow(concurrent_pool).to receive(:shutdown).and_call_original

      test_pool.shutdown

      expect(concurrent_pool).to have_received(:shutdown)
      test_pool.wait_for_termination(1)
    end
  end

  describe "#wait_for_termination" do
    it "delegates to underlying pool" do
      test_pool = described_class.new(concurrency)
      concurrent_pool = test_pool.instance_variable_get(:@pool)
      allow(concurrent_pool).to receive(:wait_for_termination).and_call_original

      test_pool.shutdown
      test_pool.wait_for_termination(5)

      expect(concurrent_pool).to have_received(:wait_for_termination).with(5)
    end

    it "waits for all tasks to complete" do
      results = []
      mutex = Mutex.new

      5.times do |i|
        pool.post do
          mutex.synchronize { results << i }
        end
      end

      pool.shutdown
      pool.wait_for_termination(1)

      expect(results.sort).to eq([0, 1, 2, 3, 4])
    end
  end
end
