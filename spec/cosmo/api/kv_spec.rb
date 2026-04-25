# frozen_string_literal: true

RSpec.describe Cosmo::API::KV do
  subject(:kv) { described_class.new("test_kv_bucket") }

  before { destroy_streams }
  after { destroy_streams }

  describe "#set and #get" do
    it "stores and retrieves a value" do
      kv.set("mykey", "myvalue")
      expect(kv.get("mykey")).to eq("myvalue")
    end

    it "returns nil for missing key" do
      expect(kv.get("nonexistent")).to be_nil
    end
  end

  describe "#delete" do
    it "deletes a key" do
      kv.set("todelete", "val")
      kv.delete("todelete")
      expect(kv.get("todelete")).to be_nil
    end
  end

  describe "#keys" do
    it "returns active keys" do
      kv.set("a", "1")
      kv.set("b", "2")
      keys = kv.keys
      expect(keys).to include("a", "b")
    end

    it "respects limit" do
      5.times { |i| kv.set("key#{i}", i.to_s) }
      expect(kv.keys(limit: 3).size).to eq(3)
    end
  end

  describe "#purge" do
    it "purges a key" do
      kv.set("p", "v")
      kv.purge("p")
      expect(kv.get("p")).to be_nil
    end
  end

  describe "#size / #count" do
    it "returns number of active keys" do
      expect(kv.size).to eq(0)
      kv.set("x", "1")
      kv.set("y", "2")
      expect(kv.size).to eq(2)
    end
  end

  describe "#clean" do
    it "removes all keys" do
      kv.set("c1", "v1")
      kv.set("c2", "v2")
      kv.clean
      expect(kv.size).to eq(0)
    end
  end
end
