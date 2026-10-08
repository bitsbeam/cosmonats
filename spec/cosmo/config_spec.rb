# frozen_string_literal: true

require "tempfile"

RSpec.describe Cosmo::Config do
  let(:config_path) { File.expand_path("../../fixtures/test_config.yml", __dir__) }
  let(:test_config) do
    {
      concurrency: 10,
      setup: {
        streams: {
          test_stream: {
            subjects: ["%{name}.>"],
            max_age: 3600,
            duplicate_window: 60
          }
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
      config = { setup: { streams: { test: { max_age: 60 } } } }
      described_class.normalize!(config)
      expect(config[:setup][:streams][:test][:max_age]).to eq(60 * 1_000_000_000)
    end

    it "converts duplicate_window to nanoseconds" do
      config = { setup: { streams: { test: { duplicate_window: 30 } } } }
      described_class.normalize!(config)
      expect(config[:setup][:streams][:test][:duplicate_window]).to eq(30 * 1_000_000_000)
    end

    it "formats subject strings" do
      config = { consumers: { jobs: { default: { subject: "jobs.%{name}.>" } } } }
      described_class.normalize!(config)
      expect(config[:consumers][:jobs][:default][:subject]).to eq("jobs.default.>")
    end

    it "formats subjects arrays" do
      config = { setup: { streams: { test: { subjects: %w[%{name}.> %{name}.events] } } } }
      described_class.normalize!(config)
      expect(config[:setup][:streams][:test][:subjects]).to eq(%w[test.> test.events])
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
    it "retrieves a value by key" do
      instance = described_class.new
      instance.load(nil, overrides: { concurrency: 5 })
      expect(instance[:concurrency]).to eq(5)
    end
  end

  describe "#fetch" do
    it "returns config value when key exists" do
      instance = described_class.new
      instance.load(nil, overrides: { concurrency: 5 })
      expect(instance.fetch(:concurrency)).to eq(5)
    end

    it "returns default value when key does not exist" do
      instance = described_class.new
      expect(instance.fetch(:nonexistent, 10)).to eq(10)
    end

    it "returns default argument when key does not exist" do
      instance = described_class.new
      result = instance.fetch(:concurrency, 1)
      expect(result).to eq(1)
    end
  end

  describe "#dig" do
    it "digs into config hash" do
      instance = described_class.new
      instance.load(nil, overrides: { setup: { streams: { test: { subjects: ["test.>"] } } } })
      expect(instance.dig(:setup, :streams, :test, :subjects)).to eq(["test.>"])
    end

    it "returns nil when path does not exist" do
      instance = described_class.new
      expect(instance.dig(:nonexistent, :path)).to be_nil
    end
  end

  describe "#load" do
    let(:instance) { described_class.new }

    def load_yaml(yaml)
      Tempfile.create(["cosmo", ".yml"]) do |file|
        file.write(yaml)
        file.flush
        instance.load(file.path)
      end
    end

    it "loads the built-in defaults without a file" do
      instance.load(nil)

      expect(instance).to include(timeout: 25, concurrency: 1, max_retries: 3)
      expect(instance.dig(:setup, :jobs).keys).to eq([:default])
      expect(instance.dig(:consumers, :jobs, :default)).to include(subject: "jobs.default.>", ack_wait: 60, priority: 15)
    end

    it "loads the shipped config exactly like no file" do
      instance.load(described_class::DEFAULTS_FILE)

      expect(instance).to eq(described_class.new.tap { _1.load(nil) })
    end

    it "merges the file over the defaults, keeping what it leaves out" do
      load_yaml(<<~YAML)
        concurrency: 10
        consumers:
          jobs:
            default:
              ack_wait: 300
      YAML

      expect(instance).to include(concurrency: 10, timeout: 25)
      expect(instance.dig(:consumers, :jobs, :default)).to include(ack_wait: 300, max_deliver: 30, subject: "jobs.default.>")
      expect(instance.dig(:setup, :jobs).keys).to eq([:default])
    end

    it "replaces the default job stream with the streams the file lists" do
      load_yaml(<<~YAML)
        setup:
          jobs:
            critical:
              subjects: ["jobs.%{name}.>"]
        consumers:
          jobs:
            critical:
              subject: jobs.%{name}.>
      YAML

      expect(instance.dig(:setup, :jobs).keys).to eq([:critical])
      expect(instance.dig(:consumers, :jobs).keys).to eq([:critical])
      expect(instance.dig(:setup, :jobs, :critical, :subjects)).to eq(["jobs.critical.>"])
    end

    it "lets overrides such as command-line flags win over the file" do
      Tempfile.create(["cosmo", ".yml"]) do |file|
        file.write("concurrency: 10\nhttp:\n  port: 9090\n  host: 0.0.0.0\n")
        file.flush
        instance.load(file.path, overrides: { concurrency: 3, http: { port: 8080 } })
      end

      expect(instance).to include(concurrency: 3, http: { port: 8080, host: "0.0.0.0" })
    end

    it "rejects the service streams" do
      expect { load_yaml("setup:\n  jobs:\n    dead:\n      max_msgs: 1\n") }
        .to raise_error(Cosmo::ConfigError, /`setup.jobs.dead` is a Cosmo service stream/)
      expect { load_yaml("consumers:\n  jobs:\n    scheduled:\n      max_deliver: 5\n") }
        .to raise_error(Cosmo::ConfigError, /`consumers.jobs.scheduled` is a Cosmo service stream/)
    end

    it "rejects batch_expiry, which moved to Cosmo.configure" do
      expect { load_yaml("batch_expiry: 60\n") }.to raise_error(Cosmo::ConfigError, /config.batches.expiry/)
    end
  end

  describe "service settings" do
    it "defaults to enabled services with one replica" do
      config = described_class.new

      expect(config.replicas).to eq(1)
      expect(config.scheduled.enabled).to be(true)
      expect(config.dead.to_h).to eq(enabled: true, max_age: 604_800, max_msgs: 10_000, max_bytes: -1)
      expect(config.batches.expiry).to eq(259_200)
    end

    it "keeps settings from Cosmo.configure when a config file is loaded afterwards" do
      Cosmo.configure do |config|
        config.replicas = 3
        config.dead.max_age = "14d"
      end

      described_class.load(nil)

      expect(described_class.replicas).to eq(3)
      expect(described_class.dead.max_age).to eq("14d")
    end
  end

  describe "#logger and #log_level" do
    let(:output) { StringIO.new }

    around do |example|
      original = Cosmo::Logger.instance
      example.run
    ensure
      Cosmo::Logger.instance = original
    end

    it "sends Cosmo's logging to the configured logger" do
      logger = Logger.new(output)
      Cosmo.configure { |config| config.logger = logger }

      Cosmo::Logger.info "hello"

      expect(described_class.instance.logger).to be(logger)
      expect(output.string).to include("hello")
    end

    it "drops trace lines when the configured logger has no trace level" do
      Cosmo.configure do |config|
        config.logger = Logger.new(output)
        config.log_level = :debug
      end

      expect { Cosmo::Logger.trace "polling" }.not_to raise_error
      expect(output.string).to be_empty
    end

    it "accepts the trace level for Cosmo's own logger" do
      Cosmo.configure do |config|
        config.logger = Cosmo::Logger::Instance.new(output)
        config.log_level = :trace
      end

      Cosmo::Logger.trace "polling"

      expect(output.string).to include("TRACE", "polling")
    end

    it "lets COSMO_LOG_LEVEL win over the configured level" do
      previous = ENV.fetch("COSMO_LOG_LEVEL", nil)
      ENV["COSMO_LOG_LEVEL"] = "warn"
      Cosmo.configure do |config|
        config.logger = Cosmo::Logger::Instance.new(output)
        config.log_level = :debug
      end

      Cosmo::Logger.info "ignored"
      Cosmo::Logger.warn "kept"

      expect(output.string).not_to include("ignored")
      expect(output.string).to include("kept")
    ensure
      ENV["COSMO_LOG_LEVEL"] = previous
    end
  end

  describe "#server_middleware" do
    let(:custom) { Class.new }

    it "starts with the built-in middleware" do
      expect(described_class.server_middleware.map(&:klass)).to eq([Cosmo::Middleware::Limit, Cosmo::Middleware::Busy, Cosmo::Middleware::Totals])
    end

    it "keeps middleware registered through Cosmo.configure when a config file is loaded afterwards" do
      Cosmo.configure do |config|
        config.server_middleware { |chain| chain.add custom }
      end

      described_class.load("spec/support/cosmo.yml")

      expect(described_class.server_middleware.map(&:klass)).to eq([Cosmo::Middleware::Limit, Cosmo::Middleware::Busy, Cosmo::Middleware::Totals, custom])
    end
  end
end
