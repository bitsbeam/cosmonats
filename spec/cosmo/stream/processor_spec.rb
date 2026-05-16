# frozen_string_literal: true

RSpec.describe Cosmo::Stream::Processor do
  let(:concurrency) { 3 }
  let(:pool)        { Cosmo::Utils::ThreadPool.new(concurrency) }
  let(:running)     { Concurrent::AtomicBoolean.new }
  let(:results)     { Results.instance }
  let(:config)      { { storage: "file", retention: "limits", duplicate_window: 120 * Cosmo::Config::NANO, discard: "old", allow_direct: true } }
  let(:processor)   { described_class.new(pool, running, {}) }

  def create_stream(name)
    client.create_stream(name, config.merge(subjects: ["#{name}.>"]))
  end

  around(:example) do |example|
    prepare_streams { example.run }
  end

  context "with successful job execution" do
    context "with #process_one" do
      before do
        stub_const("EventProcessor", Class.new do
          include Cosmo::Stream

          options stream: :test_events,
                  fetch_timeout: 1.0,
                  consumer: { subjects: ["test_events.>"] }

          def process_one
            Results.instance << message.data
            message.ack
          end
        end)
      end

      before do
        create_stream("test_events")
        processor.run
      end
      after do
        processor.stop
      end

      it "calls process_one for each incoming message" do
        EventProcessor.publish({ type: "greeting", name: "Alice" }, subject: "test_events.hello")
        wait_until(timeout: 5) { results.any? }

        expect(results.first).to eq("type" => "greeting", "name" => "Alice")
      end

      it "processes multiple messages published to the same stream" do
        %w[Alice Bob Charlie].each { |name| EventProcessor.publish({ name: name }, subject: "test_events.hello") }
        wait_until(timeout: 5) { results.size >= 3 }

        expect(results.map { |r| r["name"] }).to contain_exactly("Alice", "Bob", "Charlie")
      end

      it "deserializes JSON payloads via the default serializer" do
        client.publish("test_events.raw", %({"key":"value","number":42}))
        wait_until(timeout: 5) { results.any? }

        expect(results.first).to eq("key" => "value", "number" => 42)
      end

      it "stops consuming messages after an explicit shutdown" do
        EventProcessor.publish({ event: "first" }, subject: "test_events.work")
        wait_until(timeout: 5) { results.any? }

        processor.stop

        EventProcessor.publish({ event: "after-stop" }, subject: "test_events.late")
        sleep 1.5

        expect(results.map { |r| r["event"] }).not_to include("after-stop")
      end
    end

    context "with #process" do
      before do
        stub_const("OrderProcessor", Class.new do
          include Cosmo::Stream

          options stream: :test_orders,
                  batch_size: 10,
                  fetch_timeout: 1.0,
                  consumer: { subjects: ["test_orders.>"] }

          def process(messages)
            Results.instance.concat(messages.map(&:data))
            messages.each(&:ack)
          end
        end)
      end

      before do
        create_stream("test_orders")
        processor.run
      end
      after do
        processor.stop
      end

      it "passes all messages to the overridden process method" do
        3.times { |i| OrderProcessor.publish({ order_id: i }, subject: "test_orders.new") }
        wait_until(timeout: 5) { results.size >= 3 }

        expect(results.map { |r| r["order_id"] }).to contain_exactly(0, 1, 2)
      end

      it "provides Message objects with correct data to the process method" do
        OrderProcessor.publish({ tag: "batch-test" }, subject: "test_orders.new")
        wait_until(timeout: 5) { results.any? }

        expect(results.first).to eq("tag" => "batch-test")
      end
    end

    context "with processor filtering" do
      let(:processor) { described_class.new(pool, running, { processors: ["FilteredProcessor"] }) }

      before do
        stub_const("FilteredProcessor", Class.new do
          include Cosmo::Stream

          options stream: :test_filtered,
                  fetch_timeout: 1.0,
                  consumer: { subjects: ["test_filtered.>"] }

          def process_one
            Results.instance << "filtered:#{message.data["val"]}"
            message.ack
          end
        end)

        stub_const("IgnoredProcessor", Class.new do
          include Cosmo::Stream

          options stream: :test_ignored,
                  fetch_timeout: 1.0,
                  consumer: { subjects: ["test_ignored.>"] }

          def process_one
            Results.instance << "ignored:#{message.data["val"]}"
            message.ack
          end
        end)
      end

      before do
        create_stream("test_filtered")
        create_stream("test_ignored")
        processor.run
      end
      after do
        processor.stop
      end

      it "only creates subscriptions for the specified processor" do
        expect(processor.consumers.size).to eq(1)
      end

      it "processes messages for the filtered-in processor" do
        IgnoredProcessor.publish({ val: "no" }, subject: "test_ignored.item")
        sleep 1.5
        FilteredProcessor.publish({ val: "yes" }, subject: "test_filtered.item")
        wait_until(timeout: 5) { results.any? }

        expect(results).not_to include("ignored:no")
        expect(stream_size("test_ignored")).to eq(1)
        expect(results).to eq(["filtered:yes"])
      end
    end

    context "with multiple processors" do
      before do
        stub_const("StreamAlpha", Class.new do
          include Cosmo::Stream

          options stream: :test_alpha,
                  fetch_timeout: 1.0,
                  consumer: { subjects: ["test_alpha.>"] }

          def process_one
            Results.instance << "alpha:#{message.data["id"]}"
            message.ack
          end
        end)

        stub_const("StreamBeta", Class.new do
          include Cosmo::Stream

          options stream: :test_beta,
                  fetch_timeout: 1.0,
                  consumer: { subjects: ["test_beta.>"] }

          def process_one
            Results.instance << "beta:#{message.data["id"]}"
            message.ack
          end
        end)
      end

      before do
        create_stream("test_alpha")
        create_stream("test_beta")
        processor.run
      end
      after do
        processor.stop
      end

      it "creates subscriptions for every registered stream class" do
        expect(processor.consumers.size).to eq(2)
      end

      it "independently routes messages to the correct processor" do
        StreamAlpha.publish({ id: 1 }, subject: "test_alpha.item")
        StreamBeta.publish({ id: 2 }, subject: "test_beta.item")

        wait_until(timeout: 5) { results.size >= 2 }

        expect(results).to contain_exactly("alpha:1", "beta:2")
      end
    end

    context "with static configuration" do
      before do
        stub_const("StaticProcessor", Class.new do
          include Cosmo::Stream

          def process_one
            Results.instance << message.data["tag"]
            message.ack
          end
        end)
      end

      before do
        create_stream("test_static")
        Cosmo::Config.instance_variable_set(:@instance, nil)
        Cosmo::Config.instance.set(:consumers, :streams, [
                                     {
                                       stream: "test_static",
                                       consumer_name: "consumer-static-test",
                                       class: "StaticProcessor",
                                       batch_size: 10,
                                       fetch_timeout: 1.0,
                                       consumer: { subjects: ["test_static.>"] }
                                     }
                                   ])
        processor.run
      end
      after do
        processor.stop
        Cosmo::Config.instance_variable_set(:@instance, nil)
      end

      it "creates a subscription for each entry in the configuration" do
        expect(processor.consumers.size).to eq(1)
      end

      it "processes messages from a statically-configured stream" do
        client.publish("test_static.item", %({"tag":"static-test"}))
        wait_until(timeout: 5) { results.any? }

        expect(results).to include("static-test")
      end

      it "skips configuration entries whose class name cannot be resolved" do
        Cosmo::Config.instance_variable_set(:@instance, nil)
        Cosmo::Config.instance.set(:consumers, :streams, [
                                     { stream: "test_static", class: "DoesNotExistXYZ",
                                       consumer: { subjects: ["test_static.>"] } }
                                   ])

        processor = described_class.new(Cosmo::Utils::ThreadPool.new(1), Concurrent::AtomicBoolean.new, {})
        expect { processor.run }.not_to raise_error
        expect(processor.consumers).to be_empty
      ensure
        processor&.stop
      end
    end

    context "with a paused stream" do
      let(:ttl_recheck) { 0.1 }

      before do
        stub_const("PauseTestProcessor", Class.new do
          include Cosmo::Stream

          options stream: :test_pause,
                  fetch_timeout: 1.0,
                  consumer: { subjects: ["test_pause.>"] }

          def process_one
            Results.instance << message.data
            message.ack
          end
        end)
      end

      before do
        create_stream("test_pause")
        client.pause_stream("test_pause")
        stub_const("Cosmo::Processor::STREAM_PAUSED_RECHECK_TTL", ttl_recheck)
        processor.run
      end
      after do
        processor.stop
      end

      it "does not consume messages while the stream is paused" do
        PauseTestProcessor.publish({ event: "after-unpause" }, subject: "test_pause.item")
        sleep(Cosmo::Processor::STREAMS_PAUSED_IDLE_SLEEP + 0.2) # ensure the processor has time to check the paused state at least once
        expect(results).to be_empty
        expect(stream_size("test_pause")).to eq(1)

        client.unpause_stream("test_pause")
        sleep(ttl_recheck * 2) # let cache expire so processor unpauses

        wait_until(timeout: 5) { results.any? }
        expect(results.first).to eq("event" => "after-unpause")
      end
    end

    context "when fetch_timeout is invalid" do
      before { stub_const("Cosmo::Stream::Data::DEFAULTS", Cosmo::Stream::Data::DEFAULTS.merge(fetch_timeout: 1)) }

      it "emits a warning and falls back to the default, when 0" do
        stub_const("ZeroTimeoutProcessor", Class.new do
          include Cosmo::Stream

          options stream: :test_zero_timeout,
                  fetch_timeout: 0,
                  consumer: { subjects: ["test_zero_timeout.>"] }

          def process_one
            Results.instance << message.data["tag"]
            message.ack
          end
        end)

        create_stream("test_zero_timeout")

        expect(Cosmo::Logger).to receive(:warn)
          .with("Ignoring `fetch_timeout: 0.0` (causes high CPU usage) with #{Cosmo::Stream::Data::DEFAULTS[:fetch_timeout]}s instead")
          .at_least(:once)

        processor = described_class.new(pool, running, {})
        processor.run
        ZeroTimeoutProcessor.publish({ tag: "zero-timeout" }, subject: "test_zero_timeout.item")
        wait_until(timeout: 5) { results.any? }

        processor.stop
        expect(results).to include("zero-timeout")
      end

      it "emits a warning and falls back to the default, when -3" do
        stub_const("NegTimeoutProcessor", Class.new do
          include Cosmo::Stream

          options stream: :test_neg_timeout,
                  fetch_timeout: -3,
                  consumer: { subjects: ["test_neg_timeout.>"] }

          def process_one
            Results.instance << message.data["tag"]
            message.ack
          end
        end)

        create_stream("test_neg_timeout")

        expect(Cosmo::Logger).to receive(:warn)
          .with("Ignoring `fetch_timeout: -3.0` (causes high CPU usage) with #{Cosmo::Stream::Data::DEFAULTS[:fetch_timeout]}s instead")
          .at_least(:once)

        processor = described_class.new(pool, running, {})
        processor.run
        NegTimeoutProcessor.publish({ tag: "neg-timeout" }, subject: "test_neg_timeout.item")
        wait_until(timeout: 15) { results.any? }

        processor.stop
        expect(results).to include("neg-timeout")
      end
    end

    context "with a custom serializer" do
      before do
        require "base64"

        stub_const("SymbolSerializer", Module.new do
          module_function

          def serialize(data)
            Base64.encode64(Marshal.dump(data))
          end

          def deserialize(payload)
            Marshal.load(Base64.decode64(payload))
          end
        end)

        stub_const("SymbolizedProcessor", Class.new do
          include Cosmo::Stream

          options stream: :test_custom_serial,
                  fetch_timeout: 1.0,
                  consumer: { subjects: ["test_custom_serial.>"] },
                  publisher: { serializer: SymbolSerializer }

          def process_one
            Results.instance << message.data
            message.ack
          end
        end)
      end

      before do
        create_stream("test_custom_serial")
        processor.run
      end
      after do
        processor.stop
      end

      it "deserializes raw message data using the custom serializer" do
        value = { key: "sym", number: 7 }
        payload = Base64.encode64(Marshal.dump(value))

        client.publish("test_custom_serial.item", payload)
        wait_until(timeout: 5) { results.any? }

        expect(results.first).to eq(key: "sym", number: 7)
      end

      it "cannot deserialize corrupted data" do
        client.publish("test_custom_serial.item", "marshall mathers")
        sleep 2

        expect(results).to be_empty
      end

      it "uses the custom serializer for the full publish→receive round-trip" do
        SymbolizedProcessor.publish({ name: "round-trip" }, subject: "test_custom_serial.item")
        wait_until(timeout: 5) { results.any? }

        expect(results.first).to eq(name: "round-trip")
      end
    end
  end

  context "with failed job execution" do
    before do
      stub_const("FaultyProcessor", Class.new do
        include Cosmo::Stream

        options stream: :test_errors,
                fetch_timeout: 1.0,
                consumer: { subjects: ["test_errors.>"] }

        def process_one
          raise StandardError, "intentional error" if message.data["fail"]

          Results.instance << message.data["tag"]
          message.ack
        end
      end)
    end

    before do
      create_stream("test_errors")
      processor.run
    end
    after do
      processor.stop
    end

    it "catches StandardError and continues processing subsequent messages" do
      FaultyProcessor.publish({ fail: true }, subject: "test_errors.item")
      sleep 2
      FaultyProcessor.publish({ fail: false, tag: "canary" }, subject: "test_errors.item")

      wait_until(timeout: 5) { results.include?("canary") }

      expect(results).to include("canary")
    end

    it "does not add the errored message's data to results" do
      FaultyProcessor.publish({ fail: true, tag: "broken" }, subject: "test_errors.item")
      sleep 2
      FaultyProcessor.publish({ fail: false, tag: "ok" }, subject: "test_errors.item")

      wait_until(timeout: 5) { results.include?("ok") }

      expect(results).not_to include("broken")
    end
  end
end
