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
    end

    # #size reads back through a fresh KV#keys watch, which isn't guaranteed to reflect a
    # just-published key the instant #add's publish is acked -- wait for it instead of reading
    # #size synchronously right after, same reasoning as the batch_spec fix.
    it "tracks a message" do
      before_size = busy.size
      busy.add(message)
      wait_until(timeout: 5) { busy.size == before_size + 1 }
    end
  end

  describe "#delete" do
    before do
      allow(message).to receive(:data).and_return("{}")
      busy.add(message)
      wait_until(timeout: 5) { busy.size == 1 }
    end

    it "removes the message" do
      busy.delete(message)
      wait_until(timeout: 5) { busy.size.zero? } # rubocop:disable Style/ZeroLengthPredicate -- Integer, not a collection
    end
  end

  describe "#with" do
    before do
      allow(message).to receive(:data).and_return("{}")
    end

    it "tracks message while block executes and removes after" do
      busy.with(message) do
        wait_until(timeout: 5) { busy.size == 1 }
      end
      wait_until(timeout: 5) { busy.size.zero? } # rubocop:disable Style/ZeroLengthPredicate -- Integer, not a collection
    end

    it "removes message even if block raises" do
      expect { busy.with(message) { raise "error" } }.to raise_error("error")
      wait_until(timeout: 5) { busy.size.zero? } # rubocop:disable Style/ZeroLengthPredicate -- Integer, not a collection
    end
  end

  describe "#list" do
    before do
      allow(message).to receive(:data).and_return(Cosmo::Utils::Json.dump({ class: "MyWorker", args: [] }))
      busy.add(message)
      wait_until(timeout: 5) { busy.size == 1 }
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
