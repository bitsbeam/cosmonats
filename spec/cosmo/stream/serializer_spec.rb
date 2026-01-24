# frozen_string_literal: true

RSpec.describe Cosmo::Stream::Serializer do
  describe ".serialize" do
    it "converts hash to JSON string" do
      data = { key: "value", nested: { data: 123 } }
      result = described_class.serialize(data)
      expect(result).to eq('{"key":"value","nested":{"data":123}}')
    end

    it "converts array to JSON string" do
      data = [1, 2, 3]
      result = described_class.serialize(data)
      expect(result).to eq("[1,2,3]")
    end

    it "handles nil values" do
      data = { key: nil }
      result = described_class.serialize(data)
      expect(result).to eq('{"key":null}')
    end

    it "handles nested structures" do
      data = { users: [{ name: "John", age: 30 }, { name: "Jane", age: 25 }] }
      result = described_class.serialize(data)
      expect(result).to eq('{"users":[{"name":"John","age":30},{"name":"Jane","age":25}]}')
    end
  end

  describe ".deserialize" do
    it "parses JSON string to Ruby object" do
      payload = '{"key":"value","nested":{"data":123}}'
      result = described_class.deserialize(payload)
      expect(result).to eq({ "key" => "value", "nested" => { "data" => 123 } })
    end

    it "parses array JSON" do
      payload = "[1,2,3]"
      result = described_class.deserialize(payload)
      expect(result).to eq([1, 2, 3])
    end

    it "handles null values" do
      payload = '{"key":null}'
      result = described_class.deserialize(payload)
      expect(result["key"]).to be_nil
    end
  end
end
