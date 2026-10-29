# frozen_string_literal: true

class MyJob
  include Cosmo::Job
end

class Child < MyJob
end

class CustomChild < MyJob
  options stream: :custom
end

class CustomCustomChild < CustomChild
  include Cosmo::Job
end

RSpec.describe Cosmo::Job do
  it "#options" do
    expect(MyJob.default_options).to eq({ dead: true, retry: 3, stream: :default, limit: nil })
    expect(Child.default_options).to eq({ dead: true, retry: 3, stream: :default, limit: nil })
    expect(CustomChild.default_options).to eq({ dead: true, retry: 3, stream: :custom, limit: nil })
    expect(CustomCustomChild.default_options).to eq({ dead: true, retry: 3, stream: :custom, limit: nil })

    CustomChild.default_options[:stream] = :none
    expect(CustomChild.default_options).to eq({ dead: true, retry: 3, stream: :none, limit: nil })
    expect(CustomCustomChild.default_options).to eq({ dead: true, retry: 3, stream: :custom, limit: nil })
  end

  describe "#concurrency_options" do
    it "defaults retry_in to half of duration when not specified" do
      stub_const("ConcurrentJob", Class.new(MyJob) { options limit: { duration: 30, concurrency: 2 } })

      expect(ConcurrentJob.concurrency_options).to include(duration: 30, retry_in: 15)
    end

    it "uses the explicit retry_in when given" do
      stub_const("ConcurrentJob", Class.new(MyJob) { options limit: { duration: 30, concurrency: 2, retry_in: 5 } })

      expect(ConcurrentJob.concurrency_options).to include(duration: 30, retry_in: 5)
    end
  end

  describe "#retry_in" do
    it "returns nil when retry_in is not configured" do
      expect(MyJob.retry_in).to be_nil
    end

    it "returns the configured proc" do
      handler = ->(count, _exception) { count * 10 }
      stub_const("RetryInJob", Class.new(MyJob) { options retry_in: ->(count, _exception) { count * 10 } })

      expect(RetryInJob.retry_in).to be_a(Proc)
      expect(RetryInJob.retry_in.call(3, nil)).to eq(handler.call(3, nil))
    end

    it "is inherited through default_options like other options" do
      stub_const("RetryInParent", Class.new(MyJob) { options retry_in: ->(count, _exception) { count } })
      stub_const("RetryInChild", Class.new(RetryInParent))

      expect(RetryInChild.retry_in).to be(RetryInParent.default_options[:retry_in])
    end

    it "raises ArgumentError when retry_in is not callable" do
      expect do
        Class.new(MyJob) { options retry_in: 5 }
      end.to raise_error(Cosmo::ArgumentError, /retry_in must be callable/)
    end
  end

  describe "#set" do
    before do
      Cosmo::Config.load("spec/support/cosmo.yml")
      create_streams(Cosmo::Config.dig(:setup, :jobs))
    end

    def payload(stream, seq = 1)
      message = client.get_message(stream, seq: seq)
      [message, Cosmo::Utils::Json.parse(message.data)]
    end

    it "enqueues on the given stream with the given options, keeping a trailing hash argument" do
      jid = MyJob.set(stream: :critical, retry: 0, dead: false).perform_async(1, { url: "https://example.com" })

      message, data = payload("critical")
      expect(message.subject).to eq("jobs.critical.my_job")
      expect(data).to include(jid: jid, args: [1, { url: "https://example.com" }], retry: 0, dead: false)
    end

    it "dispatches a delayed job to the given stream" do
      MyJob.set(stream: :critical).perform_in(60, 1)
      MyJob.set(stream: :critical).perform_at(Time.now + 60, 2)

      expect(payload("scheduled", 1).first.headers).to include("X-Stream" => "critical", "X-Subject" => "jobs.critical.my_job")
      expect(payload("scheduled", 2).first.headers).to include("X-Stream" => "critical")
    end

    it "leaves the class options untouched" do
      MyJob.set(stream: :critical).perform_async(1)

      expect(MyJob.default_options[:stream]).to eq(:default)
    end

    it "enqueues in bulk with the given options" do
      MyJob.set(stream: :critical, retry: 0).perform_bulk([[1], [2]])

      expect(payload("critical", 2).last).to include(args: [2], retry: 0)
    end

    it "rejects options the message does not carry" do
      expect { MyJob.set(limit: { duration: 5 }) }.to raise_error(Cosmo::ArgumentError, /unknown job options limit/)
      expect { MyJob.set(queue: :critical) }.to raise_error(Cosmo::ArgumentError, /use stream: instead of queue:/)
    end
  end

  describe "#perform_bulk" do
    before do
      Cosmo::Config.load("spec/support/cosmo.yml")
      create_streams(Cosmo::Config.dig(:setup, :jobs))
    end

    def payloads(stream, count)
      (1..count).map { Cosmo::Utils::Json.parse(client.get_message(stream, seq: _1).data) }
    end

    it "enqueues one job per argument list, in order, across chunks" do
      stub_const("Cosmo::Job::Enqueuer::CHUNK_SIZE", 2)

      jids = MyJob.perform_bulk([[1], [2], [3, { url: "https://example.com" }]])

      expect(payloads("default", 3).map { _1[:args] }).to eq([[1], [2], [3, { url: "https://example.com" }]])
      expect(payloads("default", 3).map { _1[:jid] }).to eq(jids)
    end

    it "delays every job" do
      MyJob.perform_bulk([[1], [2]], in: 60)

      expect(stream_size("scheduled")).to eq(2)
      expect(client.get_message("scheduled", seq: 2).headers).to include("X-Stream" => "default")
    end

    it "counts every job in the current batch" do
      batch = Cosmo::Batch.new
      batch.jobs { MyJob.perform_bulk([[1], [2], [3]]) }

      expect(Cosmo::API::Batch.new(batch.bid).stats).to include(total: 3)
    end

    it "rejects anything but a list of argument arrays" do
      expect { MyJob.perform_bulk([1, 2]) }.to raise_error(Cosmo::ArgumentError, /array of argument arrays/)
      expect(stream_size("default")).to eq(0)
    end
  end
end
