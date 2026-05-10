# frozen_string_literal: true

# rubocop:disable Style/RedundantFetchBlock
RSpec.describe Cosmo::Utils::TTLCache do
  subject(:cache) { described_class.new }

  describe "#set / #get" do
    it "stores and retrieves a value" do
      cache.set(:key, "value")
      expect(cache.get(:key)).to eq("value")
    end

    it "returns nil for a missing key" do
      expect(cache.get(:missing)).to be_nil
    end

    it "returns nil after TTL expires" do
      cache.set(:key, "value", ttl: 0.01)
      sleep 0.02
      expect(cache.get(:key)).to be_nil
    end

    it "returns value before TTL expires" do
      cache.set(:key, "value", ttl: 10)
      expect(cache.get(:key)).to eq("value")
    end

    it "stores nil values" do
      cache.set(:key, nil)
      expect(cache.get(:key)).to be_nil
    end
  end

  describe "#fetch" do
    it "yields and stores value on cache miss" do
      yielded = false
      result = cache.fetch(:key) do
        yielded = true
        42
      end
      expect(yielded).to be true
      expect(result).to eq(42)
    end

    it "does not yield on cache hit" do
      cache.set(:key, 99)
      calls = 0
      result = cache.fetch(:key) do
        calls += 1
        0
      end
      expect(calls).to eq(0)
      expect(result).to eq(99)
    end

    it "returns the cached value on subsequent calls without yielding" do
      cache.fetch(:key) { "first" }
      result = cache.fetch(:key) { "second" }
      expect(result).to eq("first")
    end

    it "re-yields after TTL expires" do
      call_count = 0
      cache.fetch(:key, ttl: 0.01) do
        call_count += 1
        "v1"
      end
      sleep 0.02
      cache.fetch(:key, ttl: 0.01) do
        call_count += 1
        "v2"
      end
      expect(call_count).to eq(2)
    end

    it "does not call #get on a cache miss (returns result directly)" do
      expect(cache).not_to receive(:get)
      result = cache.fetch(:key) { "value" }
      expect(result).to eq("value")
    end

    it "calls #get on a cache hit" do
      cache.set(:key, "cached")
      expect(cache).to receive(:get).with(:key).and_call_original
      cache.fetch(:key) { "ignored" }
    end

    it "supports ttl option" do
      cache.fetch(:key, ttl: 0.01) { "short-lived" }
      expect(cache.get(:key)).to eq("short-lived")
      sleep 0.02
      expect(cache.get(:key)).to be_nil
    end
  end

  describe "thread safety" do
    it "does not raise under concurrent access" do
      threads = 10.times.map do |i|
        Thread.new { cache.fetch("key#{i % 3}", ttl: 1) { i } }
      end
      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
# rubocop:enable Style/RedundantFetchBlock
