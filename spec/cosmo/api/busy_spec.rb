# frozen_string_literal: true

RSpec.describe Cosmo::API::Busy do
  subject(:busy) { described_class.new }

  let(:message) { double("message", metadata: double(sequence: double(stream: 42), stream: "jobs")) }

  before do
    busy.instance_variable_get(:@kv).clean rescue nil
  end

  after do
    busy.instance_variable_get(:@kv).clean rescue nil
  end

  describe ".instance" do
    it "returns a singleton" do
      expect(described_class.instance).to be(described_class.instance)
    end
  end

  describe "#add and #size" do
    before do
      allow(message).to receive_message_chain(:data).and_return("{}")
      allow(Time).to receive(:now).and_return(double(to_i: 1_000_000))
    end

    it "tracks a message" do
      expect { busy.add(message) }.to change { busy.size }.by(1)
    end
  end

  describe "#delete" do
    before do
      allow(message).to receive(:data).and_return("{}")
      allow(Time).to receive(:now).and_return(double(to_i: 1_000_000))
      busy.add(message)
    end

    it "removes the message" do
      expect { busy.delete(message) }.to change { busy.size }.by(-1)
    end
  end

  describe "#with" do
    before do
      allow(message).to receive(:data).and_return("{}")
      allow(Time).to receive(:now).and_return(double(to_i: 1_000_000))
    end

    it "tracks message while block executes and removes after" do
      busy.with(message) do
        expect(busy.size).to eq(1)
      end
      expect(busy.size).to eq(0)
    end

    it "removes message even if block raises" do
      expect { busy.with(message) { raise "error" } }.to raise_error("error")
      expect(busy.size).to eq(0)
    end
  end

  describe "#list" do
    before do
      allow(message).to receive(:data).and_return(Cosmo::Utils::Json.dump({ class: "MyWorker", args: [] }))
      allow(Time).to receive(:now).and_return(double(to_i: 1_000_000))
      busy.add(message)
    end

    it "returns list of busy entries" do
      entries = busy.list
      expect(entries).to be_an(Array)
      expect(entries.first).to include(:worker, :started_at, :stream)
    end

    it "respects limit" do
      2.times do |i|
        m = double("msg#{i}", metadata: double(sequence: double(stream: i), stream: "jobs"), data: "{}")
        busy.add(m)
      end
      expect(busy.list(limit: 1).size).to eq(1)
    end
  end
end
