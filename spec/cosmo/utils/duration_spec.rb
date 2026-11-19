# frozen_string_literal: true

RSpec.describe Cosmo::Utils::Duration do
  describe ".parse" do
    it "passes numbers through" do
      expect(described_class.parse(90)).to eq(90)
      expect(described_class.parse(1.5)).to eq(1.5)
    end

    it "reads numeric strings as seconds" do
      expect(described_class.parse("120")).to eq(120.0)
      expect(described_class.parse("0.5")).to eq(0.5)
    end

    it "reads a single unit" do
      expect(described_class.parse("20s")).to eq(20)
      expect(described_class.parse("61m")).to eq(3660)
      expect(described_class.parse("7d")).to eq(604_800)
      expect(described_class.parse("1mo")).to eq(2_592_000)
    end

    it "sums compound durations" do
      expect(described_class.parse("1h1m")).to eq(3660)
      expect(described_class.parse("1d12h")).to eq(129_600)
      expect(described_class.parse("2w3d4h5m6s")).to eq(1_483_506)
      expect(described_class.parse("1mo2d")).to eq(2_764_800)
      expect(described_class.parse("1m1mo")).to eq(2_592_060)
    end

    it "rejects invalid durations" do
      ["", "1h 1m", "h1", "1x", "1.5h", "1h-", "-1m"].each do |value|
        expect { described_class.parse(value) }.to raise_error(Cosmo::ArgumentError, /invalid duration/)
      end
    end
  end
end
