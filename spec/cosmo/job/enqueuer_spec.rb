# frozen_string_literal: true

RSpec.describe Cosmo::Job::Enqueuer do
  before do
    Cosmo::Config.load("spec/support/cosmo.yml")
    create_streams(Cosmo::Config.dig(:setup, :jobs))
  end

  describe ".enqueue" do
    it "publishes the job to its stream and returns its jid" do
      jid = described_class.enqueue("ReportJob", [1, "two"], { stream: :default })

      message = client.get_message("default", seq: 1)
      expect(message.subject).to eq("jobs.default.report_job")
      expect(message.headers).to include("Nats-Msg-Id" => jid)
      expect(Cosmo::Utils::Json.parse(message.data)).to include(jid: jid, class: "ReportJob", args: [1, "two"])
    end

    it "stamps the batch id on a job that joins a batch" do
      batch = Cosmo::Batch.new
      described_class.enqueue("ReportJob", [], { stream: :default }, batch: batch)

      expect(Cosmo::Utils::Json.parse(client.get_message("default", seq: 1).data)).to include(batch_id: batch.bid)
    end

    it "raises StreamNotFoundError when the stream does not exist" do
      expect { described_class.enqueue("ReportJob", [], { stream: :missing }) }
        .to raise_error(Cosmo::StreamNotFoundError, "Missing stream `missing`")
    end
  end
end
