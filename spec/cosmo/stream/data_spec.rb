# frozen_string_literal: true

RSpec.describe Cosmo::Stream::Data do
  describe "DEFAULTS" do
    it "defines default batch_size" do
      expect(described_class::DEFAULTS[:batch_size]).to eq(100)
    end

    it "defines default consumer config" do
      consumer = described_class::DEFAULTS[:consumer]
      expect(consumer[:ack_policy]).to eq("explicit")
      expect(consumer[:max_deliver]).to eq(1)
      expect(consumer[:max_ack_pending]).to eq(3)
      expect(consumer[:ack_wait]).to eq(30)
      expect(consumer[:subjects]).to eq(["%{name}.>"])
    end

    it "defines default publisher config" do
      publisher = described_class::DEFAULTS[:publisher]
      expect(publisher[:subject]).to eq("%{name}.default")
      expect(publisher[:serializer]).to be_nil
    end

    it "is frozen" do
      expect(described_class::DEFAULTS).to be_frozen
    end
  end
end
