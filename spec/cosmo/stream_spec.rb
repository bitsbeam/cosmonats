# frozen_string_literal: true

RSpec.describe Cosmo::Stream do
  let(:stream_class) do
    Class.new do
      include Cosmo::Stream

      def process_one
        # Implementation
      end
    end
  end
  let(:stream_instance) { stream_class.new }
  let(:message) { double("message") }

  before do
    Cosmo::Config.system.clear
    stub_const("TestStream", stream_class)
  end

  describe ".included" do
    it "extends class with ClassMethods" do
      expect(stream_class).to respond_to(:options)
      expect(stream_class).to respond_to(:publish)
      expect(stream_class).to respond_to(:default_options)
    end

    it "registers the stream class" do
      expect(Cosmo::Config.system[:streams]).to eq([TestStream])
    end
  end

  describe Cosmo::Stream::ClassMethods do
    describe "#options" do
      it "merges options into default_options" do
        stream_class.options(stream: :custom, batch_size: 50)
        expect(stream_class.default_options[:stream]).to eq(:custom)
        expect(stream_class.default_options[:batch_size]).to eq(50)
      end

      it "only merges non-nil values" do
        initial_stream = stream_class.default_options[:stream]
        stream_class.options(batch_size: 75)
        expect(stream_class.default_options[:stream]).to eq(initial_stream)
        expect(stream_class.default_options[:batch_size]).to eq(75)
      end
    end

    describe "#publish" do
      let(:publisher) { instance_double(Cosmo::Publisher) }

      before do
        allow(Cosmo::Publisher).to receive(:publish)
      end

      it "publishes data to stream" do
        stream_class.options(stream: :test_stream)
        expect(Cosmo::Publisher).to receive(:publish).with("test.subject", { key: "value" }, stream: :test_stream, serializer: nil)
        stream_class.publish({ key: "value" }, subject: "test.subject")
      end

      it "uses default subject from publisher config" do
        stream_class.options(stream: :test_stream, publisher: { subject: "default.subject" })
        expect(Cosmo::Publisher).to receive(:publish).with("default.subject", { key: "value" }, stream: :test_stream, serializer: nil)
        stream_class.publish({ key: "value" })
      end

      it "uses custom serializer from publisher config" do
        serializer = double("serializer")
        stream_class.options(publisher: { serializer: serializer })
        expect(Cosmo::Publisher).to receive(:publish).with(anything, anything, hash_including(serializer: serializer))
        stream_class.publish({ key: "value" }, subject: "test.subject")
      end
    end

    describe "#default_options" do
      it "returns default options hash" do
        expect(stream_class.default_options).to be_a(Hash)
      end

      it "inherits options from parent class" do
        parent_class = Class.new do
          include Cosmo::Stream

          options stream: :parent_stream
          def process_one; end
        end
        child_class = Class.new(parent_class)

        expect(child_class.default_options[:stream]).to eq(:parent_stream)
      end
    end

    describe "#register" do
      it "adds stream to Config.system[:streams]" do
        test_class = Class.new { include Cosmo::Stream }
        expect(Cosmo::Config.system[:streams]).to include(test_class)
      end

      it "formats subject with class name" do
        subject = stream_class.default_options.dig(:publisher, :subject)
        expect(subject).to eq(".default") # since class name is anonymous
      end
    end
  end

  describe "#process" do
    it "processes each message" do
      messages = [message, message]
      expect(stream_instance).to receive(:process_one).twice
      stream_instance.process(messages)
    end

    it "sets thread-local message" do
      allow(stream_instance).to receive(:process_one) do
        expect(Thread.current[:cosmo_message]).to eq(message)
      end
      stream_instance.process([message])
    end

    it "clears thread-local message after processing" do
      allow(stream_instance).to receive(:process_one)
      stream_instance.process([message])
      expect(Thread.current[:cosmo_message]).to be_nil
    end

    it "clears message even when error occurs" do
      allow(stream_instance).to receive(:process_one).and_raise(StandardError)
      expect { stream_instance.process([message]) }.to raise_error(StandardError)
      expect(Thread.current[:cosmo_message]).to be_nil
    end
  end

  describe "#process_many" do
    it "is aliased to process" do
      expect(stream_instance.method(:process_many)).to eq(stream_instance.method(:process))
    end
  end

  describe "#process_batch" do
    it "is aliased to process" do
      expect(stream_instance.method(:process_batch)).to eq(stream_instance.method(:process))
    end
  end

  describe "#process_one" do
    it "raises NotImplementedError by default" do
      klass = Class.new { include Cosmo::Stream }
      instance = klass.new
      expect { instance.process_one }.to raise_error(Cosmo::NotImplementedError, /process_one must be implemented/)
    end
  end

  describe "#logger" do
    it "returns Logger instance" do
      expect(stream_instance.logger).to be(Cosmo::Logger.instance)
    end
  end

  describe "#message" do
    it "returns current thread message" do
      Thread.current[:cosmo_message] = message
      expect(stream_instance.message).to eq(message)
      Thread.current[:cosmo_message] = nil
    end
  end

  describe "#publish" do
    before do
      allow(stream_class).to receive(:publish)
    end

    it "delegates to class method" do
      expect(stream_class).to receive(:publish).with({ data: "test" }, subject: "test.subject", stream: "test")
      stream_instance.publish({ data: "test" }, "test.subject", stream: "test")
    end
  end
end
