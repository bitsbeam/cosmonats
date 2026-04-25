# frozen_string_literal: true

RSpec.describe Cosmo::API::Counter do
  subject(:counter) { described_class.new("test") }

  let(:stream_name) { described_class::STREAM_NAME }

  before { destroy_streams }
  after { destroy_streams }

  describe ".instance" do
    it "returns a singleton" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe "#get" do
    it "returns 0 when no messages exist" do
      expect(counter.get(:processed)).to eq(0)
    end
  end

  describe "#increment / #incr" do
    it "increments the counter" do
      counter.increment(:processed)
      expect(counter.get(:processed)).to eq(1)
    end

    it "increments by a custom amount" do
      counter.increment(:processed, by: 5)
      expect(counter.get(:processed)).to eq(5)
    end

    it "is aliased as #incr" do
      counter.incr(:processed)
      expect(counter.get(:processed)).to eq(1)
    end
  end

  describe "#decrement / #decr" do
    it "decrements the counter" do
      counter.increment(:processed, by: 3)
      counter.decrement(:processed)
      expect(counter.get(:processed)).to eq(2)
    end

    it "is aliased as #decr" do
      counter.increment(:processed, by: 2)
      counter.decr(:processed)
      expect(counter.get(:processed)).to eq(1)
    end
  end

  describe "#with" do
    it "increments :processed when block returns true" do
      counter.with { true }
      expect(counter.get(:processed)).to eq(1)
      expect(counter.get(:failed)).to eq(0)
    end

    it "increments :failed when block returns false" do
      counter.with { false }
      expect(counter.get(:failed)).to eq(1)
      expect(counter.get(:processed)).to eq(0)
    end

    it "increments :failed on exception" do
      expect { counter.with { raise "boom" } }.not_to raise_error
      expect(counter.get(:failed)).to eq(1)
    end
  end

  describe "#reset" do
    it "resets the counter to 0" do
      counter.increment(:processed, by: 3)
      counter.reset(:processed)
      expect(counter.get(:processed)).to eq(0)
    end
  end
end
