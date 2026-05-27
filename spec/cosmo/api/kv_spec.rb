# frozen_string_literal: true

RSpec.describe Cosmo::API::KV do
  subject(:kv) { described_class.new("test_kv_bucket") }

  before { destroy_streams }
  after { destroy_streams }

  describe "#get" do
    it "returns nil for missing key" do
      expect(kv.get("nonexistent")).to be_nil
    end
  end

  describe "#set" do
    let(:ttl_kv) { described_class.new("test_kv_ttl_bucket", allow_msg_ttl: true) }

    it "stores and retrieves a value" do
      kv.set("mykey", "myvalue")
      expect(kv.get("mykey")&.value).to eq("myvalue")
    end

    it "creates a new key and returns an entry" do
      entry = ttl_kv.set("slot/0", "job-1", ttl: 30)
      expect(entry).not_to be_nil
      expect(ttl_kv.get("slot/0")&.value).to eq("job-1")
    end

    it "raises error when the key is already live" do
      ttl_kv.set("slot/0", "job-1", ttl: 30)
      expect { ttl_kv.set("slot/0", "job-2", ttl: 30) }.to raise_error(NATS::KeyValue::KeyWrongLastSequenceError)
    end

    it "reclaims a deleted key atomically" do
      ttl_kv.set("slot/0", "job-1", ttl: 30)
      ttl_kv.delete("slot/0")
      ttl_kv.set("slot/0", "job-2", ttl: 30)
      expect(ttl_kv.get("slot/0")&.value).to eq("job-2")
    end

    it "reclaims a purged key atomically" do
      ttl_kv.set("slot/0", "job-1", ttl: 30)
      ttl_kv.purge("slot/0")
      ttl_kv.set("slot/0", "job-2", ttl: 30)
      expect(ttl_kv.get("slot/0")&.value).to eq("job-2")
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
