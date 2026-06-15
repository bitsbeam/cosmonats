# frozen_string_literal: true

RSpec.describe Cosmo::API::Cron do
  subject(:api) { described_class.new }

  describe "#upsert!" do
    let(:schedule) do
      { class_name: "ReportJob", stream: "default", schedule: "@daily", args: ["weekly"], timezone: "UTC", name: "daily_report" }
    end

    it "publishes to the correct schedule subject" do
      expect(client).to receive(:publish).with(
        "cosmo.cron.default.report_job.daily_report",
        anything,
        stream: "default",
        header: hash_including("Nats-Schedule" => "@daily", "Nats-Schedule-Target" => "jobs.default.report_job")
      )
      api.upsert!(**schedule)
    end

    it "includes timezone header when present" do
      expect(client).to receive(:publish).with(
        anything, anything,
        stream: anything,
        header: hash_including("Nats-Schedule-Time-Zone" => "UTC")
      )
      api.upsert!(**schedule)
    end

    it "omits timezone header when nil" do
      expect(client).to receive(:publish).with(
        anything, anything,
        stream: anything,
        header: satisfy { |h| !h.key?("Nats-Schedule-Time-Zone") }
      )
      api.upsert!(class_name: "ReportJob", stream: "default", schedule: "@daily")
    end

    it "accepts keyword arguments to build the schedule" do
      expect(client).to receive(:publish).with(
        "cosmo.cron.default.report_job",
        anything,
        stream: "default",
        header: hash_including("Nats-Schedule" => "@hourly")
      )
      api.upsert!(class_name: "ReportJob", stream: "default", schedule: "@hourly")
    end
  end

  describe "#delete!" do
    it "purges the correct stream and subject" do
      expect(client).to receive(:purge).with("default", "cosmo.cron.default.report_job")
      api.delete!("cosmo.cron.default.report_job")
    end

    it "returns nil when subject is not found" do
      allow(client).to receive(:purge).and_raise(NATS::JetStream::Error::NotFound)
      expect(api.delete!("cosmo.cron.default.report_job")).to be_nil
    end
  end

  describe "#run_now!" do
    let(:subject_str) { "cosmo.cron.default.report_job.daily" }
    let(:msg) do
      double("msg",
             headers: { "Nats-Schedule-Target" => "jobs.default.report_job" },
             data: Cosmo::Utils::Json.dump({ class: "ReportJob", args: [], retry: 3, dead: true }))
    end

    before do
      allow(client).to receive(:get_message).with("default", subject: subject_str).and_return(msg)
    end

    it "publishes to the target subject" do
      expect(client).to receive(:publish).with(
        "jobs.default.report_job",
        satisfy { |p| Cosmo::Utils::Json.parse(p)[:class] == "ReportJob" },
        stream: "default"
      )
      api.run_now!(subject_str)
    end

    it "does nothing when schedule message is not found" do
      allow(client).to receive(:get_message).and_return(nil)
      expect(client).not_to receive(:publish)
      api.run_now!(subject_str)
    end
  end
end
