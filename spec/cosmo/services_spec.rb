# frozen_string_literal: true

RSpec.describe Cosmo::Services do
  def stream_config(name)
    client.stream_info(name).config
  end

  describe ".setup!" do
    it "creates the scheduled, dead, and internal counter streams" do
      expect(described_class.setup!).to eq(%w[scheduled dead])

      expect(stream_config("scheduled")).to have_attributes(allow_msg_schedules: true, discard: "old",
                                                            subjects: ["jobs.scheduled.>", "cosmo.cron.>"])
      expect(stream_config("dead")).to have_attributes(retention: "workqueue", max_msgs: 10_000, max_age: 604_800 * Cosmo::Config::NANO)
      expect(stream_config("_cosmototals")).to have_attributes(allow_msg_counter: true, max_age: 0)
      expect(stream_config("_cosmobatches")).to have_attributes(allow_msg_counter: true, max_age: 3 * 86_400 * Cosmo::Config::NANO)
      expect(stream_config("_cosmometrics")).to have_attributes(allow_msg_counter: true, max_age: 30 * 86_400 * Cosmo::Config::NANO)
    end

    it "applies the dead-letter retention from Cosmo.configure" do
      Cosmo.configure do |config|
        config.dead.max_age = "1d"
        config.dead.max_msgs = 50
      end

      described_class.setup!

      expect(stream_config("dead")).to have_attributes(max_age: 86_400 * Cosmo::Config::NANO, max_msgs: 50)
    end

    it "skips the streams of services that are turned off" do
      Cosmo.configure do |config|
        config.scheduled.enabled = false
        config.dead.enabled = false
        config.metrics.enabled = false
      end

      expect(described_class.setup!).to eq([])
      names = client.list_streams.map { _1.dig("config", "name") }
      expect(names).to include("_cosmototals", "_cosmobatches")
      expect(names).not_to include("scheduled", "dead", "_cosmometrics")
    end

    it "explains how to replace a dead stream left from an older version" do
      client.create_stream("dead", subjects: ["jobs.dead.>"], retention: "limits")

      expect { described_class.setup! }.to raise_error(Cosmo::Error, /existing `dead` stream has another retention policy.*nats stream rm dead/)
    end
  end

  describe "replicas" do
    it "sizes every service stream by config.replicas" do
      Cosmo.configure { |config| config.replicas = 3 }

      expect(described_class.scheduled_stream).to include(num_replicas: 3)
      expect(described_class.dead_stream).to include(num_replicas: 3)
      expect(Cosmo::API::Stats::Totals.stream_config).to include(num_replicas: 3)
      expect(Cosmo::Batch::Counters.stream_config).to include(num_replicas: 3)
    end
  end
end
