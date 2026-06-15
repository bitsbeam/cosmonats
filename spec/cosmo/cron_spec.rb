# frozen_string_literal: true

RSpec.describe Cosmo::API::Cron::Entry do
  around do |example|
    original_cron = Cosmo::Config.dig(:setup, :cron)
    example.run
    Cosmo::Config.set(:setup, :cron, original_cron)
  end

  subject(:entry) do
    described_class.new(class_name: "TestCronJob", stream: "default", expression: "@daily",
                        args: ["arg1"], timezone: "Europe/Amsterdam", name: "daily")
  end

  it "builds the correct schedule subject" do
    expect(entry.schedule_subject).to eq("cosmo.cron.default.test_cron_job.daily")
  end

  it "builds the correct target subject" do
    expect(entry.target_subject).to eq("jobs.default.test_cron_job")
  end

  describe ".normalize_expression" do
    it "leaves @-shortcuts unchanged" do
      expect(described_class.normalize_expression("@daily")).to eq("@daily")
      expect(described_class.normalize_expression("@every 30m")).to eq("@every 30m")
    end

    it "prepends a seconds field to 5-field cron expressions" do
      expect(described_class.normalize_expression("0 9 * * 1-5")).to eq("0 0 9 * * 1-5")
      expect(described_class.normalize_expression("30 6 * * 0")).to eq("0 30 6 * * 0")
    end

    it "leaves already-6-field expressions unchanged" do
      expect(described_class.normalize_expression("0 0 9 * * 1-5")).to eq("0 0 9 * * 1-5")
    end
  end

  it "produces a valid JSON job payload" do
    payload = Cosmo::Utils::Json.parse(entry.job_payload)
    expect(payload[:class]).to eq("TestCronJob")
    expect(payload[:args]).to eq(["arg1"])
    expect(payload[:retry]).to eq(Cosmo::Job::Data::DEFAULTS[:retry])
    expect(payload[:dead]).to eq(Cosmo::Job::Data::DEFAULTS[:dead])
    expect(payload[:jid]).to be_a(String).and have_attributes(length: 24)
  end

  context "without a name" do
    subject(:entry) { described_class.new(class_name: "TestCronJob", stream: "default", expression: "@hourly") }

    it "omits the name from the schedule subject" do
      expect(entry.schedule_subject).to eq("cosmo.cron.default.test_cron_job")
    end
  end

  describe "#as_json" do
    it "includes all relevant fields" do
      json = entry.as_json
      expect(json[:class]).to eq("TestCronJob")
      expect(json[:stream]).to eq("default")
      expect(json[:schedule]).to eq("@daily")
      expect(json[:timezone]).to eq("Europe/Amsterdam")
      expect(json[:args]).to eq(["arg1"])
      expect(json[:name]).to eq("daily")
      expect(json[:schedule_subject]).to eq("cosmo.cron.default.test_cron_job.daily")
      expect(json[:target_subject]).to eq("jobs.default.test_cron_job")
    end

    it "omits nil fields" do
      e = described_class.new(class_name: "TestCronJob", stream: "default", expression: "@hourly")
      expect(e.as_json).not_to have_key(:timezone)
      expect(e.as_json).not_to have_key(:name)
    end
  end
end
