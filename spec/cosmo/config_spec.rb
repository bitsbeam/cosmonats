# frozen_string_literal: true

RSpec.describe Cosmo::Config do
  let(:config_path) { File.expand_path("../../fixtures/test_config.yml", __dir__) }
  let(:test_config) do
    {
      concurrency: 10,
      streams: {
        test_stream: {
          subjects: ["%{name}.>"],
          max_age: 3600,
          duplicate_window: 60
        }
      },
      consumers: {
        jobs: {
          default: {
            subject: "jobs.%{name}.>",
            subjects: ["jobs.%{name}.>"]
          }
        }
      }
    }
  end

  describe ".parse_file" do
    it "loads and parses YAML file" do
      allow(YAML).to receive(:load_file).and_return(test_config)
      result = described_class.parse_file(config_path)
      expect(result).to be_a(Hash)
    end
  end

  describe ".normalize!" do
    it "symbolizes keys" do
      config = { "a" => 1, "b" => { "c" => 2 } }
      described_class.normalize!(config)
      expect(config).to eq({ a: 1, b: { c: 2 } })
    end

    it "converts max_age to nanoseconds" do
      config = { streams: { test: { max_age: 60 } } }
      described_class.normalize!(config)
      expect(config[:streams][:test][:max_age]).to eq(60 * 1_000_000_000)
    end

    it "converts duplicate_window to nanoseconds" do
      config = { streams: { test: { duplicate_window: 30 } } }
      described_class.normalize!(config)
      expect(config[:streams][:test][:duplicate_window]).to eq(30 * 1_000_000_000)
    end

    it "formats subject strings" do
      config = { consumers: { jobs: { default: { subject: "jobs.%{name}.>" } } } }
      described_class.normalize!(config)
      expect(config[:consumers][:jobs][:default][:subject]).to eq("jobs.default.>")
    end

    it "formats subjects arrays" do
      config = { streams: { test: { subjects: %w[%{name}.> %{name}.events] } } }
      described_class.normalize!(config)
      expect(config[:streams][:test][:subjects]).to eq(%w[test.> test.events])
    end
  end

  describe ".deliver_policy" do
    it "returns last policy" do
      expect(described_class.deliver_policy("last")).to eq({ deliver_policy: "last" })
      expect(described_class.deliver_policy(:last)).to eq({ deliver_policy: "last" })
    end

    it "returns new policy" do
      expect(described_class.deliver_policy("new")).to eq({ deliver_policy: "new" })
      expect(described_class.deliver_policy(:new)).to eq({ deliver_policy: "new" })
    end

    it "returns by_start_time policy for Time object" do
      time = Time.new(2026, 1, 26, 12, 0, 0)
      result = described_class.deliver_policy(time)
      expect(result[:deliver_policy]).to eq("by_start_time")
      expect(result[:opt_start_time]).to eq(time.iso8601)
    end

    it "returns by_start_time policy for time string" do
      time_str = "2026-01-26T12:00:00Z"
      result = described_class.deliver_policy(time_str)
      expect(result[:deliver_policy]).to eq("by_start_time")
      expect(result[:opt_start_time]).to eq(time_str)
    end

    it "returns all policy by default" do
      expect(described_class.deliver_policy(nil)).to eq({ deliver_policy: "all" })
      expect(described_class.deliver_policy(123)).to eq({ deliver_policy: "all" })
    end
  end

  describe ".instance" do
    it "returns singleton instance" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe "#[]" do
    it "delegates to dig" do
      instance = described_class.new
      expect(instance).to receive(:dig).with(:concurrency)
      instance[:concurrency]
    end
  end

  describe "#fetch" do
    it "returns config value when key exists" do
      instance = described_class.new
      instance.set(:concurrency, 5)
      expect(instance.fetch(:concurrency)).to eq(5)
    end

    it "returns default value when key does not exist" do
      instance = described_class.new
      expect(instance.fetch(:nonexistent, 10)).to eq(10)
    end

    it "returns defaults value when config is nil" do
      instance = described_class.new
      result = instance.fetch(:concurrency, 1)
      expect(result).to eq(1)
    end
  end

  describe "#dig" do
    it "digs into config hash" do
      instance = described_class.new
      instance.set(:streams, :test, :subjects, ["test.>"])
      expect(instance.dig(:streams, :test, :subjects)).to eq(["test.>"])
    end

    it "returns nil when path does not exist" do
      instance = described_class.new
      expect(instance.dig(:nonexistent, :path)).to be_nil
    end
  end

  describe "#to_h" do
    it "merges defaults and config" do
      instance = described_class.new
      instance.set(:concurrency, 5)
      result = instance.to_h
      expect(result).to be_a(Hash)
      expect(result[:concurrency]).to eq(5)
    end
  end

  describe "#set" do
    it "sets nested configuration values" do
      instance = described_class.new
      instance.set(:streams, :test, :subjects, ["test.>"])
      expect(instance.dig(:streams, :test, :subjects)).to eq(["test.>"])
    end
  end

  describe "#load" do
    it "loads configuration from file" do
      instance = described_class.new
      allow(described_class).to receive(:parse_file).with(config_path).and_return(test_config)
      instance.load(config_path)
      expect(instance[:concurrency]).to eq(10)
    end

    it "does nothing when path is nil" do
      instance = described_class.new
      expect(described_class).not_to receive(:parse_file)
      instance.load(nil)
    end
  end
end
