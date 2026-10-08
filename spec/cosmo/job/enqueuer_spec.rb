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

  describe "with client middleware" do
    let(:results) { Results.instance }

    def published
      Cosmo::Utils::Json.parse(client.get_message("default", seq: 1).data)
    end

    it "publishes the payload a middleware changed, passing it the class name and target stream" do
      Cosmo.configure do |config|
        config.client_middleware.add(Class.new do
          def call(class_name, payload, stream)
            Results.instance << [class_name, stream]
            payload[:request_id] = "req-1"
            yield
          end
        end)
      end

      described_class.enqueue("ReportJob", [1], { stream: :default })

      expect(results).to eq([["ReportJob", :default]])
      expect(published).to include(class: "ReportJob", args: [1], request_id: "req-1")
    end

    it "passes a delayed job's target stream, not the scheduled one" do
      Cosmo.configure { |config| config.client_middleware.add(Class.new { def call(_, _, stream) = (Results.instance << stream) && yield }) }

      described_class.enqueue("ReportJob", [], { stream: :default, in: 60 })

      expect(results).to eq([:default])
    end

    it "publishes nothing, returns nil, and releases the batch slot when a middleware does not yield" do
      Cosmo.configure { |config| config.client_middleware.add(Class.new { def call(*) = nil }) }
      batch = Cosmo::Batch.new

      expect(described_class.enqueue("ReportJob", [], { stream: :default }, batch: batch)).to be_nil
      expect(stream_size("default")).to eq(0)
      expect(Cosmo::API::Batch.new(batch.bid).stats).to include(total: 0, pending: 0)
    end

    it "releases the batch slot when a middleware raises" do
      Cosmo.configure { |config| config.client_middleware.add(Class.new { def call(*) = raise("middleware down") }) }
      batch = Cosmo::Batch.new

      expect { described_class.enqueue("ReportJob", [], { stream: :default }, batch: batch) }.to raise_error("middleware down")
      expect(Cosmo::API::Batch.new(batch.bid).stats).to include(total: 0, pending: 0)
    end
  end
end
