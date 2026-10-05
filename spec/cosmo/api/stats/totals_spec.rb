# frozen_string_literal: true

RSpec.describe Cosmo::API::Stats::Totals do
  subject(:counter) { described_class.instance }

  before { destroy_streams }
  after { destroy_streams }

  describe ".instance" do
    it "returns a singleton" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe "#with" do
    it "counts a block returning true as processed" do
      counter.with { true }
      expect(counter.processed).to eq(1)
      expect(counter.failed).to eq(0)
    end

    it "counts a block returning false as failed" do
      counter.with { false }
      expect(counter.failed).to eq(1)
      expect(counter.processed).to eq(0)
    end

    it "counts a raising block as failed without re-raising" do
      expect { counter.with { raise "boom" } }.not_to raise_error
      expect(counter.failed).to eq(1)
    end
  end
end
