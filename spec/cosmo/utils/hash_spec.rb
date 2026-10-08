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

  describe ".deep_merge" do
    it "merges nested hashes, the second one winning" do
      base = { a: { b: 1, c: 2 }, d: 3 }

      expect(described_class.deep_merge(base, { a: { b: 9 } })).to eq(a: { b: 9, c: 2 }, d: 3)
    end

    it "replaces anything that is not a hash on both sides" do
      expect(described_class.deep_merge({ a: [1, 2], b: { c: 1 } }, { a: [3], b: 4 })).to eq(a: [3], b: 4)
    end

    it "leaves both arguments untouched" do
      base = { a: { b: 1 } }
      described_class.deep_merge(base, { a: { b: 2 } })

      expect(base).to eq(a: { b: 1 })
    end
  end
end
