# frozen_string_literal: true

RSpec.describe Cosmo::Logger do
  describe Cosmo::Logger::Context do
    after { Thread.current[Cosmo::Logger::Context::KEY] = {} }

    describe ".with" do
      it "sets context for block" do
        described_class.with(jid: "123") do
          expect(described_class.current[:jid]).to eq("123")
        end
      end

      it "restores previous context after block" do
        described_class.with(jid: "123")
        described_class.with(jid: "456") do
          expect(described_class.current[:jid]).to eq("456")
        end
        expect(described_class.current[:jid]).to eq("123")
      end

      it "merges with existing context" do
        described_class.with(jid: "123") do
          described_class.with(key: "value") do
            expect(described_class.current[:jid]).to eq("123")
            expect(described_class.current[:key]).to eq("value")
          end
        end
      end
    end

    describe ".without" do
      it "removes keys from context" do
        described_class.with(jid: "123", key: "value")
        described_class.without(:jid)
        expect(described_class.current[:jid]).to be_nil
        expect(described_class.current[:key]).to eq("value")
      end
    end

    describe ".current" do
      it "returns current thread context" do
        expect(described_class.current).to be_a(Hash)
      end

      it "initializes empty hash if not set" do
        Thread.current[Cosmo::Logger::Context::KEY] = nil
        expect(described_class.current).to eq({})
      end
    end
  end

  describe Cosmo::Logger::SimpleFormatter do
    let(:formatter) { described_class.new }

    describe "#call" do
      it "formats log message with context" do
        Cosmo::Logger::Context.with(jid: "123") do
          result = formatter.call("INFO", Time.now, nil, "test message")
          expect(result).to include("INFO")
          expect(result).to include("test message")
          expect(result).to include("jid=123")
        end
      end

      it "includes pid and tid" do
        result = formatter.call("INFO", Time.now, nil, "test")
        expect(result).to match(/pid=\d+/)
        expect(result).to match(/tid=\w+/)
      end

      it "formats timestamp in ISO8601" do
        time = Time.new(2026, 1, 26, 12, 0, 0, 0)
        result = formatter.call("INFO", time, nil, "test")
        expect(result).to include("2026-01-26")
      end
    end

    describe "#tid" do
      it "returns thread id" do
        tid = formatter.send(:tid)
        expect(tid).to be_a(String)
      end
    end

    describe "#pid" do
      it "returns process id" do
        pid = formatter.send(:pid)
        expect(pid).to eq(Process.pid)
      end
    end
  end

  describe ".instance" do
    it "returns logger instance" do
      expect(described_class.instance).to be_a(Logger)
    end

    it "returns same instance" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe ".with" do
    it "delegates to Context.with" do
      expect(Cosmo::Logger::Context).to receive(:with).with(jid: "123")
      described_class.with(jid: "123")
    end
  end

  describe ".without" do
    it "delegates to Context.without" do
      expect(Cosmo::Logger::Context).to receive(:without).with(:jid)
      described_class.without(:jid)
    end
  end

  describe "logging methods" do
    let(:logger) { Logger.new(StringIO.new) }

    before do
      allow(described_class).to receive(:instance).and_return(logger)
    end

    it "delegates info to instance" do
      expect(logger).to receive(:info).with("test message")
      described_class.info("test message")
    end

    it "delegates error to instance" do
      expect(logger).to receive(:error).with("test error")
      described_class.error("test error")
    end

    it "delegates debug to instance" do
      expect(logger).to receive(:debug).with("test debug")
      described_class.debug("test debug")
    end

    it "delegates warn to instance" do
      expect(logger).to receive(:warn).with("test warn")
      described_class.warn("test warn")
    end

    it "delegates fatal to instance" do
      expect(logger).to receive(:fatal).with("test fatal")
      described_class.fatal("test fatal")
    end
  end
end
