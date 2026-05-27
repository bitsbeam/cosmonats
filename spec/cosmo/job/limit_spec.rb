# frozen_string_literal: true

RSpec.describe Cosmo::Job::Limit do
  subject(:bucket) { described_class.new }

  before { destroy_streams }

  describe "#acquire" do
    it "returns a String slot key on success" do
      expect(bucket.acquire("key", jid: "j1", limit: 1, duration: 60)).to be_a(String)
    end

    it "acquires up to the limit and returns nil when all slots are taken" do
      expect(bucket.acquire("key", jid: "j1", limit: 2, duration: 60)).to be_a(String)
      expect(bucket.acquire("key", jid: "j2", limit: 2, duration: 60)).to be_a(String)
      expect(bucket.acquire("key", jid: "j3", limit: 2, duration: 60)).to be_nil
    end

    it "treats different keys independently" do
      expect(bucket.acquire("key-a", jid: "j1", limit: 1, duration: 60)).to be_a(String)
      expect(bucket.acquire("key-a", jid: "j2", limit: 1, duration: 60)).to be_nil
      expect(bucket.acquire("key-b", jid: "j3", limit: 1, duration: 60)).to be_a(String)
    end
  end

  describe "#release" do
    it "frees a slot so a subsequent acquire succeeds" do
      slot = bucket.acquire("key", jid: "j1", limit: 1, duration: 60)
      expect(bucket.acquire("key", jid: "j2", limit: 1, duration: 60)).to be_nil

      bucket.release(slot)
      expect(bucket.acquire("key", jid: "j2", limit: 1, duration: 60)).to be_a(String)
    end

    it "does not raise when called with a non-existent slot" do
      expect { bucket.release("nonexistent/0") }.not_to raise_error
    end
  end
end
