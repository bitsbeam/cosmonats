# frozen_string_literal: true

RSpec.describe Cosmo::Utils::Hash do
  describe ".symbolize_keys!" do
    it "symbolizes string keys" do
      expect(described_class.symbolize_keys!({ "a" => 1 })).to eq({ a: 1 })
    end

    it "symbolizes nested hash keys" do
      expect(described_class.symbolize_keys!({ "a" => { "b" => 1 } })).to eq({ a: { b: 1 } })
    end

    it "symbolizes deeply nested hash keys" do
      expect(described_class.symbolize_keys!({ "a" => { "b" => { "c" => 2 } } })).to eq({ a: { b: { c: 2 } } })
    end

    it "symbolizes keys in arrays" do
      result = described_class.symbolize_keys!([{ "a" => 1 }, { "b" => 2 }])
      expect(result).to eq([{ a: 1 }, { b: 2 }])
    end

    it "raises error for non-symbolizable keys" do
      expect { described_class.symbolize_keys!({ 1 => 2 }) }.to raise_error(Cosmo::ArgumentError, "key cannot be converted to symbol")
    end

    it "modifies hash in place" do
      hash = { "a" => 1 }
      described_class.symbolize_keys!(hash)
      expect(hash).to eq({ a: 1 })
    end

    it "handles empty hashes" do
      expect(described_class.symbolize_keys!({})).to eq({})
    end
  end

  describe ".dup" do
    it "creates deep copy of hash" do
      original = { a: 1, b: { c: 2 } }
      copy = described_class.dup(original)

      copy[:b][:c] = 3
      expect(original[:b][:c]).to eq(2)
    end

    it "copies nested structures" do
      original = { a: [1, 2, { b: 3 }] }
      copy = described_class.dup(original)

      copy[:a][2][:b] = 4
      expect(original[:a][2][:b]).to eq(3)
    end

    it "handles frozen objects" do
      original = { a: "frozen" }.freeze
      copy = described_class.dup(original)
      expect(copy).to eq(original)
      expect(copy.object_id).not_to eq(original.object_id)
    end
  end

  describe ".keys?" do
    let(:hash) { { a: { b: { c: 1 } } } }

    it "returns true when all keys exist" do
      expect(described_class.keys?(hash, :a, :b, :c)).to be true
    end

    it "returns false when key does not exist" do
      expect(described_class.keys?(hash, :a, :x)).to be false
    end

    it "returns false when intermediate value is not a hash" do
      hash = { a: "string" }
      expect(described_class.keys?(hash, :a, :b)).to be false
    end

    it "returns true for single key" do
      expect(described_class.keys?(hash, :a)).to be true
    end

    it "returns true when value is nil but key exists" do
      hash = { a: nil }
      expect(described_class.keys?(hash, :a)).to be true
    end
  end

  describe ".set" do
    it "sets value at single key" do
      hash = {}
      described_class.set(hash, :a, 1)
      expect(hash[:a]).to eq(1)
    end

    it "sets value at nested keys" do
      hash = {}
      described_class.set(hash, :a, :b, :c, 2)

      expect(hash[:a]).to be_a(Hash)
      expect(hash[:a][:b]).to be_a(Hash)
      expect(hash[:a][:b][:c]).to eq(2)
    end

    it "overwrites existing values" do
      hash = { a: { b: 1 } }
      described_class.set(hash, :a, :b, 2)
      expect(hash[:a][:b]).to eq(2)
    end

    it "preserves sibling keys" do
      hash = { a: { b: 1, c: 2 } }
      described_class.set(hash, :a, :b, value: 3)
      expect(hash[:a][:c]).to eq(2)
    end
  end

  describe ".merge" do
    it "merges two hashes" do
      hash1 = { a: 1, b: 2 }
      hash2 = { b: 3, c: 4 }
      result = described_class.merge(hash1, hash2)
      expect(result).to eq({ a: 1, b: 3, c: 4 })
    end

    it "deep merges nested hashes" do
      hash1 = { a: { b: 1, c: 2 } }
      hash2 = { a: { b: 3, d: 4 } }
      result = described_class.merge(hash1, hash2)
      expect(result).to eq({ a: { b: 3, c: 2, d: 4 } })
    end

    it "overwrites non-hash values" do
      hash1 = { a: 1 }
      hash2 = { a: { b: 2 } }
      result = described_class.merge(hash1, hash2)
      expect(result).to eq({ a: { b: 2 } })
    end

    it "returns hash1 when hash2 is nil" do
      hash1 = { a: 1 }
      result = described_class.merge(hash1, nil)
      expect(result).to eq(hash1)
    end

    it "handles empty hashes" do
      hash1 = { a: 1 }
      hash2 = {}
      result = described_class.merge(hash1, hash2)
      expect(result).to eq({ a: 1 })
    end

    it "deeply merges complex structures" do
      hash1 = { a: { b: { c: 1, d: 2 }, e: 3 } }
      hash2 = { a: { b: { c: 10 }, f: 4 } }
      result = described_class.merge(hash1, hash2)
      expect(result).to eq({ a: { b: { c: 10, d: 2 }, e: 3, f: 4 } })
    end
  end
end
