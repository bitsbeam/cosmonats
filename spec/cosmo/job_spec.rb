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
end
