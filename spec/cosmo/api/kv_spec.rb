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

    it "creates a new key and returns the new revision" do
      seq = ttl_kv.set("slot/0", "job-1", ttl: 30)
      expect(seq).to be_a(Integer)
      expect(ttl_kv.get("slot/0")&.value).to eq("job-1")
    end

    it "raises error when the key is already live" do
      ttl_kv.set("slot/0", "job-1", ttl: 30)
      expect { ttl_kv.set("slot/0", "job-2", ttl: 30) }.to raise_error(NATS::KeyValue::KeyWrongLastSequenceError)
    end

    it "reclaims an erased key atomically" do
      ttl_kv.set("slot/0", "job-1", ttl: 30)
      ttl_kv.erase("slot/0")
      ttl_kv.set("slot/0", "job-2", ttl: 30)
      expect(ttl_kv.get("slot/0")&.value).to eq("job-2")
    end

    it "reclaims none atomically because of a tombstone" do
      # delete/purge are for non-ttl buckets. On a ttl bucket they leave a
      # KV-Operation tombstone occupying the subject's next sequence, which a
      # plain last_seq: 0 CAS can never satisfy -- use #erase instead (see
      # Job::Limit#release). Documenting this on purpose so the limitation
      # isn't rediscovered by surprise.
      ttl_kv.set("slot/0", "job-1", ttl: 30)
      ttl_kv.delete("slot/0")
      expect { ttl_kv.set("slot/0", "job-2", ttl: 30) }.to raise_error(NATS::KeyValue::KeyWrongLastSequenceError)
    end
  end

  describe "#create" do
    it "creates a new key and returns the new revision" do
      seq = kv.create("gate", "1")
      expect(seq).to be_a(Integer)
      expect(kv.get("gate")&.value).to eq("1")
    end

    it "raises when the key already exists" do
      kv.create("gate", "1")
      expect { kv.create("gate", "2") }.to raise_error(NATS::KeyValue::KeyWrongLastSequenceError)
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

    it "walks the whole bucket without a limit" do
      (described_class::LIMIT + 5).times { |i| kv.set("key#{i}", i.to_s) }
      expect(kv.keys(limit: nil).size).to eq(described_class::LIMIT + 5)
    end

    it "skips the offset" do
      5.times { |i| kv.set("key#{i}", i.to_s) }
      first = kv.keys(limit: 5)
      expect(kv.keys(limit: 5, offset: 2)).to eq(first.drop(2))
    end

    it "stops the watcher when the walk raises" do
      kv.set("a", "1")
      watcher = nil
      allow(kv.kv).to receive(:watch).and_wrap_original do |original, *args, **options|
        watcher = original.call(*args, **options)
        allow(watcher).to receive(:each).and_raise(NATS::IO::Timeout)
        allow(watcher).to receive(:stop).and_call_original
        watcher
      end

      expect { kv.keys }.to raise_error(NATS::IO::Timeout)
      expect(watcher).to have_received(:stop)
      expect(watcher._hb_task).to be_shutdown
    end
  end

  describe "#entries" do
    it "returns keys with their values in one pass" do
      kv.set("a", "1")
      kv.set("b", "2")
      expect(kv.entries(limit: nil).sort).to eq([%w[a 1], %w[b 2]])
    end

    it "respects limit and offset" do
      5.times { |i| kv.set("key#{i}", i.to_s) }
      all = kv.entries(limit: 5)
      expect(kv.entries(limit: 2, offset: 2)).to eq(all[2, 2])
    end
  end

  describe "#direct_entries" do
    it "reads every live key in the order it was last written" do
      %w[a b c d].each { kv.set(_1, "#{_1}1") }
      kv.set("a", "a2")
      kv.delete("b")
      kv.erase("c")

      expect(kv.direct_entries).to eq([%w[d d1], %w[a a2]])
    end

    it "filters keys and stops at the limit" do
      3.times { kv.set("#{_1}.meta", "m") }
      kv.set("0.ready", "r")

      expect(kv.direct_entries("*.meta").map(&:first)).to eq(%w[0.meta 1.meta 2.meta])
      expect(kv.direct_entries(limit: 2).size).to eq(2)
    end

    it "turns on direct gets for a bucket created without them, keeping its config" do
      kv
      expect(client.stream_info("KV_test_kv_bucket").config.allow_direct).to be false

      kv.set("a", "1")
      expect(kv.direct_entries).to eq([%w[a 1]])
      config = client.stream_info("KV_test_kv_bucket").config
      expect(config.allow_direct).to be true
      expect(config.max_msgs_per_subject).to eq(1)
    end
  end

  describe "#direct_count, #direct_keys and #direct_values" do
    before do
      %w[a.1 a.2 b.1].each { kv.set(_1, "v-#{_1}") }
      kv.set("a.1", "v-a.1-again")
    end

    it "counts keys under a filter on the server" do
      expect([kv.direct_count, kv.direct_count("a.>"), kv.direct_count("*.1"), kv.direct_count("c.>")]).to eq([3, 2, 2, 0])
    end

    it "lists the sorted keys without their values" do
      expect(kv.direct_keys).to eq(%w[a.1 a.2 b.1])
      expect(kv.direct_keys("a.>")).to eq(%w[a.1 a.2])
    end

    it "reads the values of the keys asked for, leaving out missing ones and deleted ones" do
      kv.delete("b.1")

      expect(kv.direct_values(%w[a.1 b.1 zzz])).to eq("a.1" => "v-a.1-again")
    end

    it "counts and lists after a key expires or is erased" do
      kv.erase("a.2")

      expect([kv.direct_count, kv.direct_keys]).to eq([2, %w[a.1 b.1]])
    end
  end

  describe "#write_many" do
    it "writes every pair in one go" do
      kv.write_many("a" => "1", "b" => "2")

      expect(kv.direct_entries.sort).to eq([%w[a 1], %w[b 2]])
    end

    it "raises when a write is refused" do
      kv
      client.delete_stream("KV_test_kv_bucket")

      expect { kv.write_many("a" => "1") }.to raise_error(StandardError)
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

    it "counts past the default key limit" do
      total = described_class::LIMIT * 2
      total.times { |i| kv.set("key#{i}", i.to_s) }
      expect(kv.size).to eq(total)
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
