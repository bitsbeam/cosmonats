# frozen_string_literal: true

RSpec.describe Cosmo::Utils::Stopwatch do
  let(:stopwatch) { described_class.new }

  describe "#initialize" do
    it "starts ticking immediately" do
      expect(stopwatch.instance_variable_get(:@started_at)).to be_a(Float)
    end
  end

  describe "#elapsed_millis" do
    it "returns elapsed time in milliseconds" do
      stopwatch
      sleep 0.02
      expect(stopwatch.elapsed_millis).to be >= 20
    end

    it "returns float with 2 decimal places" do
      stopwatch
      sleep 0.02
      expect(stopwatch.elapsed_millis.to_s.split(".").last.length).to be <= 2
    end
  end

  describe "#elapsed_seconds" do
    it "returns elapsed time in seconds" do
      stopwatch
      sleep 1.1
      expect(stopwatch.elapsed_seconds).to be >= 1.1
    end

    it "returns float with 2 decimal places" do
      stopwatch
      sleep 1.1
      expect(stopwatch.elapsed_seconds.to_s.split(".").last.length).to be <= 2
    end
  end

  describe "#reset" do
    it "resets the start time" do
      stopwatch
      sleep 0.02
      expect(stopwatch.elapsed_millis).to be >= 20

      stopwatch.reset

      sleep 0.01
      expect(stopwatch.elapsed_millis).to be >= 10
      expect(stopwatch.elapsed_millis).to be < 20
    end
  end
end
