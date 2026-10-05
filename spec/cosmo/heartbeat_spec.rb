# frozen_string_literal: true

RSpec.describe Cosmo::Heartbeat do
  subject(:heartbeat) { described_class.new(engine, options: { streams: ["default"] }) }

  let(:engine) do
    instance_double(Cosmo::Engine, state: "running", busy: 1, concurrency: 5, subscriptions: { jobs: %w[default scheduled] })
  end
  let(:processes) { Cosmo::API::Processes.instance }

  before do
    processes.instance_variable_get(:@kv).clean rescue nil
    allow(Cosmo::CLI.instance).to receive(:argv).and_return(%w[-c 5 jobs --stream default])
  end

  after do
    heartbeat.stop
    processes.instance_variable_get(:@kv).clean rescue nil
  end

  describe "#start" do
    it "registers this process with its identity, command line, and live state" do
      heartbeat.start
      wait_until(timeout: 5) { processes.size == 1 }

      info = processes.list.first
      expect(info).to include(
        identity: "#{Socket.gethostname}-#{Process.pid}",
        hostname: Socket.gethostname,
        pid: Process.pid,
        cmdline: "#{File.basename($PROGRAM_NAME)} -c 5 jobs --stream default",
        options: { streams: ["default"] },
        state: "running",
        busy: 1,
        concurrency: 5,
        subscriptions: { jobs: %w[default scheduled] },
        version: Cosmo::VERSION
      )
      expect(info[:rss]).to be_positive
      expect(info[:nats]).to include(name: Cosmo::Client.instance.name, ip: be_a(String), server_version: be_a(String))
      expect(info[:nats][:rtt]).to be_a(Float)
    end
  end

  describe "#beat" do
    it "publishes the state it has now" do
      heartbeat.start
      allow(engine).to receive(:state).and_return("quiet")
      heartbeat.beat
      wait_until(timeout: 5) { processes.list.first&.dig(:state) == "quiet" }
    end

    it "swallows NATS errors so a beat never takes the worker down" do
      allow(processes).to receive(:register).and_raise(NATS::IO::Timeout)
      expect { heartbeat.beat }.not_to raise_error
    end
  end

  describe "#stop" do
    it "removes the process right away" do
      heartbeat.start
      wait_until(timeout: 5) { processes.size == 1 }

      heartbeat.stop
      wait_until(timeout: 5) { processes.size.zero? } # rubocop:disable Style/ZeroLengthPredicate -- Integer, not a collection
    end
  end
end
