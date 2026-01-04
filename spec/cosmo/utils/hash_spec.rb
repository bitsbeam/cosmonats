# frozen_string_literal: true

RSpec.describe Cosmo::Utils::Hash do
  it ".symbolize_keys!" do
    expect(described_class.symbolize_keys!({ "a" => 1 })).to eq({ a: 1 })
    expect(described_class.symbolize_keys!({ "a" => { "b" => 1 } })).to eq({ a: { b: 1 } })
    expect(described_class.symbolize_keys!({ "a" => { "b" => { "c" => 2 } } })).to eq({ a: { b: { c: 2 } } })
    expect { described_class.symbolize_keys!({ 1 => 2 }) }.to raise_error(Cosmo::ArgumentError, "key cannot be converted to symbol")
  end
end
