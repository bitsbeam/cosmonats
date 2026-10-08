# frozen_string_literal: true

RSpec.describe Cosmo::API::Counter do
  subject(:counter) { counter_class.new("test") }

  let(:counter_class) { Cosmo::API::Stats::Totals }
  let(:stream_name) { counter_class::STREAM_NAME }

  before { destroy_streams }
  after { destroy_streams }

  describe "#get" do
    it "returns 0 when no messages exist" do
      expect(counter.get(:processed)).to eq(0)
    end
  end

  describe "#increment / #incr" do
    it "increments the counter" do
      counter.increment(:processed)
      expect(counter.get(:processed)).to eq(1)
    end

    it "increments by a custom amount" do
      counter.increment(:processed, by: 5)
      expect(counter.get(:processed)).to eq(5)
    end

    it "is aliased as #incr" do
      counter.incr(:processed)
      expect(counter.get(:processed)).to eq(1)
    end

    context "with message deduplication" do
      it "returns the resulting value on the first publish" do
        expect(counter.increment(:pending, msg_id: "job-1")).to eq(1)
      end

      it "returns nil for a duplicate msg_id instead of double-applying" do
        counter.increment(:pending, msg_id: "job-1")
        expect(counter.increment(:pending, msg_id: "job-1")).to be_nil
        expect(counter.get(:pending)).to eq(1)
      end

      it "does not dedup across distinct msg_ids" do
        counter.increment(:pending, msg_id: "job-1")
        counter.increment(:pending, msg_id: "job-2")
        expect(counter.get(:pending)).to eq(2)
      end
    end
  end

  describe "#decrement / #decr" do
    it "decrements the counter" do
      counter.increment(:processed, by: 3)
      counter.decrement(:processed)
      expect(counter.get(:processed)).to eq(2)
    end

    it "is aliased as #decr" do
      counter.increment(:processed, by: 2)
      counter.decr(:processed)
      expect(counter.get(:processed)).to eq(1)
    end
  end

  describe "#reset" do
    it "resets the counter to 0" do
      counter.increment(:processed, by: 3)
      counter.reset(:processed)
      expect(counter.get(:processed)).to eq(0)
    end
  end

  describe "stream retention" do
    it "keeps only the latest message per counter, which carries the total" do
      3.times { counter.increment(:processed) }
      counter.decrement(:processed)

      expect(client.stream_info(stream_name).state.messages).to eq(1)
      expect(counter.get(:processed)).to eq(2)
    end
  end

  describe ".setup!" do
    it "trims an existing unlimited stream to one message per counter without losing totals" do
      client.create_stream(stream_name, counter_class.stream_config.except(:max_msgs_per_subject))
      5.times { counter.increment(:processed) }
      2.times { counter.increment(:failed) }

      counter_class.setup!

      expect(client.stream_info(stream_name).state.messages).to eq(2)
      expect(counter.get(:processed)).to eq(5)
      expect(counter.get(:failed)).to eq(2)
      counter.increment(:processed)
      expect(counter.get(:processed)).to eq(6)
    end

    it "creates the stream when it is missing" do
      counter_class.setup!
      expect(client.stream_info(stream_name).config.max_msgs_per_subject).to eq(1)
    end
  end
end
