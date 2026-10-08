# frozen_string_literal: true

RSpec.describe Cosmo::API::Stats::Metrics do
  subject(:metrics) { described_class.instance }

  let(:today) { Time.now.utc.strftime("%Y%m%d") }

  describe "#record, #flush and #summary" do
    it "averages execution time over successful runs and wait time over first deliveries" do
      metrics.record("Reports::DailyJob", exec_ms: 100, wait_ms: 40)
      metrics.record("Reports::DailyJob", exec_ms: 300)
      metrics.record("Reports::DailyJob", wait_ms: 20, failed: true)
      metrics.record("OtherJob", exec_ms: 5)
      metrics.flush

      expect(metrics.summary).to eq([
                                      { job: "Reports::DailyJob", count: 2, failed: 1, exec_ms: 200.0, wait_ms: 30.0 },
                                      { job: "OtherJob", count: 1, failed: 0, exec_ms: 5.0, wait_ms: nil }
                                    ])
    end

    it "adds up across flushes" do
      metrics.record("OtherJob", exec_ms: 10)
      metrics.flush
      metrics.record("OtherJob", exec_ms: 30)
      metrics.flush

      expect(metrics.summary.first).to include(count: 2, exec_ms: 20.0)
    end
  end

  describe "#daily" do
    it "returns one entry per day, oldest first, with today's numbers last" do
      metrics.record("OtherJob", exec_ms: 50)
      metrics.flush

      days = metrics.daily("OtherJob", days: 3)

      expect(days.map { _1[:date] }.last).to eq(today)
      expect(days.size).to eq(3)
      expect(days.last).to include(count: 1, exec_ms: 50.0)
      expect(days.first).to include(count: 0, exec_ms: nil)
    end
  end

  describe ".stream_config" do
    it "keeps the counters for config.metrics.retention on config.replicas" do
      Cosmo.configure do |config|
        config.metrics.retention = "7d"
        config.replicas = 3
      end

      expect(described_class.stream_config).to include(max_age: 7 * 86_400 * Cosmo::Config::NANO, num_replicas: 3)
    end
  end
end
