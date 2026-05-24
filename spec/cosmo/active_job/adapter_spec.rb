# frozen_string_literal: true

# Minimal ActiveJob stub when the real gem is not available
unless defined?(ActiveJob)
  require "cosmo/active_job"

  module ActiveJob
    module QueueAdapters; end

    class Base
      def self.execute(hash)
        new.perform(*hash.fetch("arguments", []))
      end

      attr_reader :job_id, :queue_name, :arguments

      def initialize
        @job_id     = SecureRandom.uuid
        @queue_name = "default"
        @arguments  = []
      end

      def serialize
        {
          "job_class" => self.class.name,
          "job_id" => @job_id,
          "queue_name" => @queue_name,
          "arguments" => @arguments
        }
      end

      def perform(*); end
    end

    # Simulate the automatic patch that happens when cosmo/active_job is loaded
    # against the real ActiveJob::Base.
    Base.include(Cosmo::ActiveJobAdapter::Options)
  end
end

class TestActiveJob < ActiveJob::Base
  def initialize(queue: "default", args: [])
    super()
    @queue_name = queue
    @arguments  = args
  end
end

class CriticalJob < ActiveJob::Base
  cosmo_options retry: 5, dead: false

  def initialize
    super
    @queue_name = "critical"
    @arguments  = []
  end
end

class InheritedCriticalJob < CriticalJob
end

class OverriddenJob < CriticalJob
  cosmo_options retry: 1
end

RSpec.describe Cosmo::ActiveJobAdapter do
  describe Cosmo::ActiveJobAdapter::Options do
    it "sets cosmo_options on the class" do
      expect(CriticalJob.get_cosmo_options).to eq(retry: 5, dead: false)
    end

    it "inherits parent cosmo_options" do
      expect(InheritedCriticalJob.get_cosmo_options).to eq(retry: 5, dead: false)
    end

    it "merges overridden options without mutating parent" do
      expect(OverriddenJob.get_cosmo_options).to eq(retry: 1, dead: false)
      expect(CriticalJob.get_cosmo_options).to eq(retry: 5, dead: false)
    end

    it "returns empty hash for a job with no cosmo_options declared" do
      expect(TestActiveJob.get_cosmo_options).to eq({})
    end

    it "raises ArgumentError for unknown keys" do
      expect { TestActiveJob.cosmo_options(foo: :bar) }
        .to raise_error(ArgumentError, /Unknown cosmo_options key\(s\): foo/)
    end
  end

  describe Cosmo::ActiveJobAdapter::Executor do
    subject(:executor) { described_class.new }

    it "includes Cosmo::Job" do
      expect(described_class.ancestors).to include(Cosmo::Job)
    end

    it "has :default stream as default option" do
      expect(described_class.default_options[:stream]).to eq(:default)
    end

    describe "#perform" do
      it "calls ActiveJob::Base.execute with stringified keys" do
        job_data = { job_class: "TestActiveJob", job_id: "abc", queue_name: "default", arguments: [] }
        expect(ActiveJob::Base).to receive(:execute) do |arg|
          expect(arg).to eq(
            "job_class" => "TestActiveJob",
            "job_id" => "abc",
            "queue_name" => "default",
            "arguments" => []
          )
        end
        executor.perform(job_data)
      end
    end
  end

  describe Cosmo::ActiveJobAdapter::Adapter do
    subject(:adapter) { described_class.new }

    let(:job) { TestActiveJob.new }

    describe "#enqueue" do
      it "publishes a Cosmo job with the correct stream and no :at" do
        expect(Cosmo::Publisher).to receive(:publish_job) do |data|
          args    = data.to_args
          payload = Cosmo::Utils::Json.parse(args[1])
          expect(payload[:class]).to eq("Cosmo::ActiveJobAdapter::Executor")
          expect(payload[:args].first).to include(job_id: job.job_id)
          expect(args[2][:stream]).to eq(:default)
        end.and_return("jid-1")

        adapter.enqueue(job)
      end

      context "when the job includes Options with cosmo_options" do
        let(:job) { CriticalJob.new }

        it "applies retry and dead from cosmo_options" do
          expect(Cosmo::Publisher).to receive(:publish_job) do |data|
            payload = Cosmo::Utils::Json.parse(data.to_args[1])
            expect(payload[:retry]).to eq(5)
            expect(payload[:dead]).to eq(false)
            expect(data.to_args[2][:stream]).to eq(:critical)
          end.and_return("jid-4")

          adapter.enqueue(job)
        end
      end

      context "when cosmo_options includes stream:" do
        before do
          CriticalJob.cosmo_options stream: :jobs_critical
        end

        after do
          # Reset to original
          CriticalJob.instance_variable_set(:@cosmo_options, { retry: 5, dead: false })
        end

        it "uses the stream from cosmo_options instead of queue_name" do
          expect(Cosmo::Publisher).to receive(:publish_job) do |data|
            expect(data.to_args[2][:stream]).to eq(:jobs_critical)
          end.and_return("jid-5")

          adapter.enqueue(CriticalJob.new)
        end
      end
    end

    describe "#enqueue_at" do
      it "publishes a scheduled Cosmo job" do
        timestamp = Time.now.to_f + 60

        expect(Cosmo::Publisher).to receive(:publish_job) do |data|
          args = data.to_args
          expect(args[2][:stream]).to eq(:scheduled)
          expect(args[2][:header]).to include("X-Execute-At")
        end.and_return("jid-2")

        adapter.enqueue_at(job, timestamp)
      end
    end
  end
end
