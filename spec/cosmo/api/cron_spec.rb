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
        stream: "scheduled",
        header: { "X-Stream" => "default", "X-Subject" => "jobs.default.report_job" },
        schedule: hash_including(cron: "@daily", target: "jobs.scheduled.report_job")
      )
      api.upsert!(**schedule)
    end

    it "includes the timezone when present" do
      expect(client).to receive(:publish).with(
        anything, anything,
        stream: anything, header: anything,
        schedule: hash_including(time_zone: "UTC")
      )
      api.upsert!(**schedule)
    end

    it "omits the timezone when nil" do
      expect(client).to receive(:publish).with(
        anything, anything,
        stream: anything, header: anything,
        schedule: satisfy { |s| !s.key?(:time_zone) }
      )
      api.upsert!(class_name: "ReportJob", stream: "default", schedule: "@daily")
    end

    it "accepts keyword arguments to build the schedule" do
      expect(client).to receive(:publish).with(
        "cosmo.cron.default.report_job",
        anything,
        stream: "scheduled", header: anything,
        schedule: hash_including(cron: "@hourly")
      )
      api.upsert!(class_name: "ReportJob", stream: "default", schedule: "@hourly")
    end

    it "takes retry and dead from the job class" do
      stub_const("ReportJob", Class.new do
        include Cosmo::Job

        options retry: false, dead: false
      end)

      expect(client).to receive(:publish) do |_, payload, **|
        expect(Cosmo::Utils::Json.parse(payload)).to include(class: "ReportJob", args: ["weekly"], retry: 0, dead: false)
      end
      api.upsert!(**schedule)
    end

    it "falls back to the default retry and dead when the job class can't be loaded" do
      expect(client).to receive(:publish) do |_, payload, **|
        expect(Cosmo::Utils::Json.parse(payload)).to include(class: "ReportJob", retry: Cosmo::Job::Data.default_retry, dead: true)
      end
      api.upsert!(**schedule)
    end
  end

  describe "#all" do
    before do
      destroy_streams
      create_streams({})
      api.upsert!(class_name: "ReportJob", stream: "reports", schedule: "@daily", name: "nightly")
      api.upsert!(class_name: "SyncJob", stream: "default", schedule: "0 9 * * 1-5", timezone: "Europe/Amsterdam")
      api.upsert!(class_name: "ReportJob", stream: "reports", schedule: "@weekly", args: [1], name: "monthly")
      api.upsert!(class_name: "CleanupJob", stream: "default", schedule: "@hourly")
    end

    after { destroy_streams }

    it "lists schedules sorted by stream, class and name" do
      expect(api.all.map { _1[:schedule_subject] }).to eq(%w[
                                                            cosmo.cron.default.cleanup_job
                                                            cosmo.cron.default.sync_job
                                                            cosmo.cron.reports.report_job.monthly
                                                            cosmo.cron.reports.report_job.nightly
                                                          ])
    end

    it "reads each schedule's expression, timezone and args from NATS" do
      expect(api.all).to include(
        hash_including(class: "SyncJob", schedule: "0 0 9 * * 1-5", timezone: "Europe/Amsterdam",
                       schedule_subject: "cosmo.cron.default.sync_job", dispatch_subject: "jobs.default.sync_job"),
        hash_including(class: "ReportJob", name: "monthly", schedule: "@weekly", args: [1])
      )
    end
  end

  describe "#delete!" do
    it "purges the correct stream and subject" do
      expect(client).to receive(:purge).with("scheduled", "cosmo.cron.default.report_job")
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
             headers: { "X-Subject" => "jobs.default.report_job", "X-Stream" => "default" },
             data: Cosmo::Utils::Json.dump({ class: "ReportJob", args: [], retry: 3, dead: true }))
    end

    before do
      allow(client).to receive(:get_message).with("scheduled", subject: subject_str).and_return(msg)
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
