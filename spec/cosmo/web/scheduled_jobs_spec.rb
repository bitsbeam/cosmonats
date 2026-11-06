# frozen_string_literal: true

require "rack/mock"

RSpec.describe "Web scheduled jobs" do
  let(:app) { Cosmo::Web }
  let(:htmx) { { "HTTP_HX_REQUEST" => "true" } }
  let(:stream) { Cosmo::API::Stream.new("scheduled") }
  let(:delayed_seq) { stream.messages.find { _1.subject.start_with?("cosmo.delayed.") }.seq.to_i }

  before do
    Cosmo::Config.load("spec/support/cosmo.yml")
    create_streams(Cosmo::Config.dig(:setup, :jobs))
    Cosmo::Services.setup!
    Cosmo::Web::Cache.instance.clear
    stub_const("WebDelayedJob", Class.new do
      include Cosmo::Job

      options stream: :default, retry: 0

      def perform(*) = nil
    end)
  end

  def request(method, path, headers = {})
    status, _, body = app.call(Rack::MockRequest.env_for(path, { method: method }.merge(headers)))
    [status, body.each.to_a.join]
  end

  it "lists a delayed job with its enqueue now and delete actions" do
    jid = WebDelayedJob.perform_in(3600, "later")

    status, html = request("GET", "/jobs/scheduled", htmx)

    expect(status).to eq(200)
    expect(html).to include(jid, "WebDelayedJob", "Enqueue now", "/jobs/scheduled/run/#{delayed_seq}",
                            "/jobs/scheduled/delete/#{delayed_seq}")
  end

  it "keeps a delayed job out of the Crons tab" do
    WebDelayedJob.perform_in(3600, "later")

    expect(Cosmo::API::Cron.instance.all).to be_empty
    expect(request("GET", "/crons", htmx).last).not_to include("WebDelayedJob")
  end

  it "enqueues a delayed job now and drops its schedule" do
    WebDelayedJob.perform_in(3600, "now please")

    status, = request("PATCH", "/jobs/scheduled/run/#{delayed_seq}")

    expect(status).to eq(200)
    expect(stream_size("default")).to eq(1)
    expect(Cosmo::Utils::Json.parse(client.get_message("default", seq: 1).data)).to include(class: "WebDelayedJob", args: ["now please"])
    expect(stream_size("scheduled")).to eq(0)
  end

  it "deletes a delayed job so it never runs" do
    WebDelayedJob.perform_in(3600, "never")

    status, = request("DELETE", "/jobs/scheduled/delete/#{delayed_seq}")

    expect(status).to eq(200)
    expect(stream_size("scheduled")).to eq(0)
    expect(stream_size("default")).to eq(0)
  end

  it "does not delete a cron schedule" do
    Cosmo::API::Cron.instance.upsert!(class_name: "WebDelayedJob", stream: "default", schedule: "@daily", name: "daily")
    cron_seq = client.js.get_last_msg("scheduled", "cosmo.cron.default.web_delayed_job.daily").seq

    request("DELETE", "/jobs/scheduled/delete/#{cron_seq}")
    request("PATCH", "/jobs/scheduled/run/#{cron_seq}")

    expect(Cosmo::API::Cron.instance.all).to include(hash_including(class: "WebDelayedJob"))
    expect(stream_size("default")).to eq(0)
  end

  describe "purging" do
    before do
      stub_const("OtherWebJob", Class.new { include Cosmo::Job })
      3.times { |i| WebDelayedJob.perform_in(3600, i) }
      2.times { |i| OtherWebJob.perform_in(3600, i) }
      Cosmo::API::Cron.instance.upsert!(class_name: "WebDelayedJob", stream: "default", schedule: "@daily", name: "daily")
    end

    def delayed_subjects
      stream.messages.map(&:subject).select { _1.start_with?("cosmo.delayed.") }
    end

    it "offers a purge for the tab and for each class" do
      html = request("GET", "/jobs/scheduled", htmx).last

      expect(html).to include("Purge all", "/jobs/scheduled/purge?class=web_delayed_job", "/jobs/scheduled/purge?class=other_web_job")
    end

    it "purges every delayed job of one class and reports how many" do
      status, html = request("DELETE", "/jobs/scheduled/purge?class=web_delayed_job")

      expect(status).to eq(200)
      expect(html).to include("Purged 3 scheduled web_delayed_job jobs")
      expect(delayed_subjects).to all(start_with("cosmo.delayed.other_web_job."))
      expect(delayed_subjects.size).to eq(2)
    end

    it "purges every delayed job, and leaves the cron schedule" do
      _, html = request("DELETE", "/jobs/scheduled/purge")

      expect(html).to include("Purged 5 scheduled jobs")
      expect(delayed_subjects).to be_empty
      expect(Cosmo::API::Cron.instance.all).to include(hash_including(class: "WebDelayedJob"))
    end

    it "refuses a class that would widen the purge" do
      statuses = ["*", ">", "web_delayed_job.>", "a.b"].map { request("DELETE", "/jobs/scheduled/purge?class=#{Rack::Utils.escape(_1)}").first }

      expect(statuses).to all(eq(404))
      expect(delayed_subjects.size).to eq(5)
    end
  end

  context "with scheduling turned off" do
    before { Cosmo.configure { |config| config.scheduled.enabled = false } }

    it "answers 404 to both actions" do
      expect(request("PATCH", "/jobs/scheduled/run/1").first).to eq(404)
      expect(request("DELETE", "/jobs/scheduled/delete/1").first).to eq(404)
      expect(request("DELETE", "/jobs/scheduled/purge").first).to eq(404)
    end
  end
end
