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

  describe "#processed and #failed" do
    it "reads each counter independently" do
      2.times { counter.increment(:processed) }
      counter.increment(:failed)

      expect(counter.processed).to eq(2)
      expect(counter.failed).to eq(1)
    end
  end
end
