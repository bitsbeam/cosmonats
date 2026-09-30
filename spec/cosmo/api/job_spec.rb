# frozen_string_literal: true

RSpec.describe Cosmo::API::Job do
  let(:stream_name) { "testjobs" }
  let(:raw_data) { Cosmo::Utils::Json.dump({ class: "MyWorker", args: [1, 2], jid: "abc123" }) }
  let(:headers) do
    { "X-Stream" => "jobs", "X-Subject" => "jobs.default.MyWorker", "X-Execute-At" => "1700000000", "Nats-Time-Stamp" => "2023-11-14T22:13:20Z" }
  end
  let(:message) { double("message", data: raw_data, seq: 5, headers: headers, subject: "jobs.default.MyWorker") }

  subject(:job) { described_class.new(stream_name, message) }

  describe "#data" do
    it "parses message data as JSON" do
      expect(job.data).to include(class: "MyWorker", args: [1, 2])
    end

    it "memoizes the result" do
      expect(job.data).to be(job.data)
    end
  end

  describe "#seq" do
    it "returns the message sequence number" do
      expect(job.seq).to eq(5)
    end
  end

  describe "#headers" do
    it "returns message headers" do
      expect(job.headers).to eq(headers)
    end
  end

  describe "#execute_at" do
    it "returns X-Execute-At as integer" do
      expect(job.execute_at).to eq(1_700_000_000)
    end

    it "returns nil when header missing" do
      allow(message).to receive(:headers).and_return({})
      expect(job.execute_at).to be_nil
    end
  end

  describe "#x_stream" do
    it "returns X-Stream header" do
      expect(job.x_stream).to eq("jobs")
    end
  end

  describe "#x_subject" do
    it "returns X-Subject header" do
      expect(job.x_subject).to eq("jobs.default.MyWorker")
    end
  end

  describe "#subject" do
    it "returns message subject" do
      expect(job.subject).to eq("jobs.default.MyWorker")
    end
  end

  describe "#stream" do
    it "returns stream name" do
      expect(job.stream).to eq(stream_name)
    end
  end

  describe "#timestamp" do
    it "returns Nats-Time-Stamp header" do
      expect(job.timestamp).to eq("2023-11-14T22:13:20Z")
    end
  end

  describe "error details" do
    let(:headers) do
      { "X-Error-Class" => "Timeout::Error", "X-Error-Message" => "execution expired", "X-Error-Backtrace" => "a.rb:1 | b.rb:2" }
    end

    it "reads the error headers" do
      expect(job.error_class).to eq("Timeout::Error")
      expect(job.error_message).to eq("execution expired")
      expect(job.error_backtrace).to eq("a.rb:1 | b.rb:2")
      expect(job).to be_error
    end

    it "is not an error without the headers" do
      allow(message).to receive(:headers).and_return({})
      expect(job).not_to be_error
    end
  end
end
