# frozen_string_literal: true

RSpec.describe Cosmo::Utils::Json do
  it ".parse" do
    expect(described_class.parse("1")).to eq(1)
    expect(described_class.parse("[]")).to eq([])
    expect(described_class.parse("{}")).to eq({})
    expect(described_class.parse(%({"a": 1}))).to eq({ a: 1 })
    expect(described_class.parse(%({"a": {"b": "2"}}))).to eq({ a: { b: "2" } })
    expect(described_class.parse(%({a: 1}))).to be_nil
    expect(described_class.parse(%('))).to be_nil
    expect(described_class.parse(%({"a": {"b": "2"}}), max_nesting: 1)).to be_nil
    expect(described_class.parse(%({"a": {"b": "2"}}), max_nesting: 2)).to eq({ a: { b: "2" } })
    expect(described_class.parse(%({"a": {"b": "2"}}), max_nesting: 2, symbolize_names: false)).to eq({ "a" => { "b" => "2" } })
  end

  it ".dump" do
    expect(described_class.dump("Class")).to eq(%("Class"))
    expect(described_class.dump({ a: { b: "2" } })).to eq(%({"a":{"b":"2"}}))
    expect(described_class.dump({ a: { b: "2" } })).to eq(%({"a":{"b":"2"}}))

    a = []
    b = []
    a.push(b)
    b.push(a)
    expect(described_class.dump(a)).to be_nil
  end
end
