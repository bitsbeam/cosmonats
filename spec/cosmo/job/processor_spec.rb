# frozen_string_literal: true

RSpec.describe Cosmo::Job::Processor do
  let(:pool) { instance_double(Cosmo::Utils::ThreadPool) }
  let(:running) { Concurrent::AtomicBoolean.new }
  let(:processor) { described_class.new(pool, running) }
  let(:client) { instance_double(Cosmo::Client) }
  let(:consumer) { double("consumer") }

  before do
    allow(Cosmo::Client).to receive(:instance).and_return(client)
    allow(Cosmo::Config).to receive(:dig).with(:consumers, :jobs).and_return(nil)
    running.make_true
  end

  describe "#initialize" do
    it "inherits from Processor" do
      expect(processor).to be_a(Cosmo::Processor)
    end
  end

  describe "#setup (private)" do
    let(:jobs_config) do
      {
        default: { subject: "jobs.default.>", priority: 10 },
        high: { subject: "jobs.high.>", priority: 5 }
      }
    end

    before do
      allow(Cosmo::Config).to receive(:dig).with(:consumers, :jobs).and_return(jobs_config)
      allow(client).to receive(:subscribe).and_return(consumer)
    end

    it "sets up consumers for each stream" do
      expect(client).to receive(:subscribe).with("jobs.default.>", "consumer-default", {})
      expect(client).to receive(:subscribe).with("jobs.high.>", "consumer-high", {})
      processor.send(:setup)
    end

    it "builds weights array based on priority" do
      processor.send(:setup)
      weights = processor.instance_variable_get(:@weights)
      expect(weights.count(:default)).to eq(10)
      expect(weights.count(:high)).to eq(5)
    end
  end

  describe "#work_loop (private)" do
    before do
      processor.instance_variable_set(:@weights, [:default])
      processor.instance_variable_set(:@consumers, { default: consumer })
      allow(pool).to receive(:post).and_yield
      allow(processor).to receive(:fetch_messages)
    end

    it "fetches messages for weighted streams" do
      running.make_false # Stop after one iteration
      thread = Thread.new { processor.send(:work_loop) }
      sleep 0.1
      thread.kill
    end

    it "handles RejectedExecutionError during shutdown" do
      allow(pool).to receive(:post).and_raise(Concurrent::RejectedExecutionError)
      running.make_false
      expect { processor.send(:work_loop) }.not_to raise_error
    end
  end

  describe "#schedule_loop (private)" do
    let(:message) { double("message") }
    let(:metadata) { double("metadata") }
    let(:header) { { "X-Stream" => "default", "X-Subject" => "jobs.default.test", "X-Execute-At" => "1000", "Nats-Expected-Stream" => "scheduled" } }

    before do
      processor.instance_variable_set(:@consumers, { scheduled: consumer })
      allow(message).to receive(:header).and_return(header)
      allow(message).to receive(:data).and_return("{}")
      allow(message).to receive(:ack)
      allow(message).to receive(:nak)
    end

    it "publishes scheduled messages when time is reached" do
      allow(Time).to receive(:now).and_return(Time.at(1001))

      # Mock fetch_messages to return messages once then raise NATS::Timeout
      call_count = 0
      allow(processor).to receive(:fetch_messages) do |*_args, &block|
        call_count += 1
        raise NATS::Timeout unless call_count == 1

        block.call([message])
      end

      allow(client).to receive(:publish)
      allow(message).to receive(:ack)

      running.make_false
      processor.send(:schedule_loop)
    end

    it "naks messages when time not reached" do
      allow(Time).to receive(:now).and_return(Time.at(500))

      # Mock fetch_messages to return messages once then raise NATS::Timeout
      call_count = 0
      allow(processor).to receive(:fetch_messages) do |*_args, &block|
        call_count += 1
        raise NATS::Timeout unless call_count == 1

        block.call([message])
      end

      allow(message).to receive(:nak)

      running.make_false
      processor.send(:schedule_loop)
    end
  end

  describe "#process (private)" do
    let(:message) { double("message") }
    let(:metadata) { double("metadata", num_delivered: 1) }
    let(:data) { { jid: "123", class: "TestJob", args: %w[arg1 arg2], retry: 3, dead: true } }
    let(:worker_instance) { double("worker") }

    before do
      allow(message).to receive(:data).and_return(Cosmo::Utils::Json.dump(data))
      allow(message).to receive(:metadata).and_return(metadata)
      allow(message).to receive(:ack)
      # Logger.with can be called with or without block
      allow(Cosmo::Logger).to receive(:with) do |*_args, &block|
        block&.call
      end
      allow(Cosmo::Logger).to receive(:without)
      allow(Cosmo::Logger).to receive(:info)
      allow(Cosmo::Logger).to receive(:debug)
    end

    it "processes valid job successfully" do
      worker_class = Class.new do
        attr_accessor :jid

        def perform(*args); end
      end
      stub_const("TestJob", worker_class)

      expect_any_instance_of(worker_class).to receive(:perform).with("arg1", "arg2")
      expect(message).to receive(:ack)
      processor.send(:process, [message])
    end

    it "handles job failure with retries" do
      worker_class = Class.new do
        attr_accessor :jid

        def perform(*_args)
          raise StandardError, "Job failed"
        end
      end
      stub_const("TestJob", worker_class)

      expect(message).to receive(:nak).with(delay: anything)
      processor.send(:process, [message])
    end

    it "moves job to DLQ when retries exhausted" do
      allow(metadata).to receive(:num_delivered).and_return(4)
      worker_class = Class.new do
        attr_accessor :jid

        def perform(*_args)
          raise StandardError, "Job failed"
        end
      end
      stub_const("TestJob", worker_class)

      expect(client).to receive(:publish).with("jobs.dead.test_job", anything)
      expect(message).to receive(:ack)
      processor.send(:process, [message])
    end

    it "logs malformed payload" do
      allow(message).to receive(:data).and_return("invalid json")

      processor.send(:process, [message])
    end

    it "logs when worker class not found" do
      processor.send(:process, [message])
    end
  end

  describe "#handle_failure (private)" do
    let(:message) { double("message") }
    let(:metadata) { double("metadata", num_delivered: 1) }
    let(:data) { { jid: "123", class: "TestJob", retry: 3, dead: true } }

    before do
      allow(message).to receive(:metadata).and_return(metadata)
      allow(message).to receive(:data).and_return("{}")
      allow(Cosmo::Logger).to receive(:debug)
    end

    it "naks message with exponential backoff when retries remain" do
      expect(message).to receive(:nak).with(delay: anything)
      processor.send(:handle_failure, message, data)
    end

    it "moves to DLQ when retries exhausted and dead enabled" do
      allow(metadata).to receive(:num_delivered).and_return(4)
      expect(client).to receive(:publish).with("jobs.dead.test_job", "{}")
      expect(message).to receive(:ack)
      processor.send(:handle_failure, message, data)
    end

    it "terminates message when retries exhausted and dead disabled" do
      allow(metadata).to receive(:num_delivered).and_return(4)
      data[:dead] = false
      expect(message).to receive(:term)
      processor.send(:handle_failure, message, data)
    end
  end
end
