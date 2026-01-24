# frozen_string_literal: true

RSpec.describe "Cosmo Error Classes" do
  describe Cosmo::Error do
    it "inherits from StandardError" do
      expect(Cosmo::Error.new).to be_a(StandardError)
    end

    it "accepts custom message" do
      error = Cosmo::Error.new("Custom error message")
      expect(error.message).to eq("Custom error message")
    end
  end

  describe Cosmo::ArgumentError do
    it "inherits from Cosmo::Error" do
      expect(Cosmo::ArgumentError.new).to be_a(Cosmo::Error)
    end

    it "accepts custom message" do
      error = Cosmo::ArgumentError.new("Invalid argument")
      expect(error.message).to eq("Invalid argument")
    end
  end

  describe Cosmo::NotImplementedError do
    it "inherits from Cosmo::Error" do
      expect(Cosmo::NotImplementedError.new).to be_a(Cosmo::Error)
    end

    it "accepts custom message" do
      error = Cosmo::NotImplementedError.new("Method not implemented")
      expect(error.message).to eq("Method not implemented")
    end
  end

  describe Cosmo::ConfigNotFoundError do
    it "inherits from Cosmo::Error" do
      expect(Cosmo::ConfigNotFoundError.new("/path/to/config")).to be_a(Cosmo::Error)
    end

    it "formats error message with config file path" do
      error = Cosmo::ConfigNotFoundError.new("/path/to/config.yml")
      expect(error.message).to eq("No such file /path/to/config.yml")
    end
  end

  describe Cosmo::StreamNotFoundError do
    it "inherits from Cosmo::Error" do
      expect(Cosmo::StreamNotFoundError.new("test_stream")).to be_a(Cosmo::Error)
    end

    it "formats error message with stream name" do
      error = Cosmo::StreamNotFoundError.new("test_stream")
      expect(error.message).to eq("Missing stream `test_stream`")
    end
  end
end
