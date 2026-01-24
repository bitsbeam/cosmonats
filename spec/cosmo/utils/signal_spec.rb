# frozen_string_literal: true

RSpec.describe Cosmo::Utils::Signal do
  describe ".trap" do
    it "creates new instance with signals" do
      signal = described_class.trap(:INT, :TERM)
      expect(signal).to be_a(described_class)
    end
  end

  describe "#initialize" do
    it "traps specified signals" do
      expect(Signal).to receive(:trap).with(:INT)
      expect(Signal).to receive(:trap).with(:TERM)
      described_class.new(:INT, :TERM)
    end
  end

  describe "#wait" do
    it "waits for signal and returns it" do
      handler = described_class.new

      Thread.new do
        sleep 0.1
        handler.push(:INT)
      end

      result = handler.wait
      expect(result).to eq(:INT)
    end

    it "blocks until signal received" do
      handler = described_class.new

      received = false
      thread = Thread.new do
        handler.wait
        received = true
      end

      sleep 0.01
      expect(received).to be false

      handler.push(:TERM)
      thread.join(0.1)
      expect(received).to be true
    end
  end

  describe "#push" do
    it "pushes signal to the queue" do
      handler = described_class.new
      handler.push(:HUP)

      result = handler.wait
      expect(result).to eq(:HUP)
    end
  end
end
