# frozen_string_literal: true

RSpec.describe Cosmo::CLI do
  subject(:cli) { described_class.new }

  let(:config_file) { File.expand_path("../../fixtures/test_config.yml", __dir__) }

  before do
    allow(Cosmo::Config).to receive(:load)
    allow(Cosmo::Engine).to receive(:run)
  end

  describe ".run" do
    it "creates new instance and calls run" do
      expect(described_class.instance).to receive(:run)
      described_class.run
    end
  end

  describe ".instance" do
    it "returns singleton instance" do
      instance1 = described_class.instance
      instance2 = described_class.instance
      expect(instance1).to be(instance2)
    end
  end

  describe "#run" do
    before do
      allow(ARGV).to receive(:shift).and_return("jobs")
    end

    it "parses flags and runs engine" do
      ARGV.replace([])
      expect(cli).to receive(:load_config).with(anything)
      expect(cli).to receive(:require_files).with(nil)
      expect(Cosmo::Engine).to receive(:run).with("jobs")

      # Suppress banner output
      expect { cli.run }.to output(anything).to_stdout
    end
  end

  describe "#parse (private)" do
    it "parses concurrency flag" do
      ARGV.replace(%w[-c 5 jobs])
      flags, command, _options = cli.send(:parse)
      expect(flags[:concurrency]).to eq(5)
      expect(command).to eq("jobs")
    end

    it "parses config flag" do
      ARGV.replace(%w[-C /path/to/config.yml jobs])
      flags, command, _options = cli.send(:parse)
      expect(flags[:config_file]).to eq("/path/to/config.yml")
      expect(command).to eq("jobs")
    end

    it "parses require flag" do
      ARGV.replace(%w[-r /path/to/require jobs])
      flags, command, _options = cli.send(:parse)
      expect(flags[:require]).to eq("/path/to/require")
      expect(command).to eq("jobs")
    end

    it "parses timeout flag" do
      ARGV.replace(%w[-t 30 jobs])
      flags, command, _options = cli.send(:parse)
      expect(flags[:timeout]).to eq(30)
      expect(command).to eq("jobs")
    end
  end

  describe "#load_config (private)" do
    it "raises error when config file does not exist" do
      expect { cli.send(:load_config, "/nonexistent.yml") }.to raise_error(Cosmo::ConfigNotFoundError)
    end

    it "loads config when file exists" do
      allow(File).to receive(:exist?).with(config_file).and_return(true)
      expect(Cosmo::Config).to receive(:load).with(config_file)
      cli.send(:load_config, config_file)
    end

    it "tries default path when no path provided" do
      allow(File).to receive(:exist?).and_return(false)
      expect(Cosmo::Config).to receive(:load).with(nil)
      cli.send(:load_config, nil)
    end
  end

  describe "#require_files (private)" do
    it "requires directory of files" do
      dir = File.expand_path("../../fixtures", __dir__)
      allow(File).to receive(:directory?).with(dir).and_return(true)
      allow(Dir).to receive(:[]).with("#{dir}/*.rb").and_return(["#{dir}/file1.rb", "#{dir}/file2.rb"])
      expect(cli).to receive(:require).with("#{dir}/file1.rb")
      expect(cli).to receive(:require).with("#{dir}/file2.rb")
      cli.send(:require_files, dir)
    end

    it "requires single file" do
      file = "/path/to/file.rb"
      allow(File).to receive(:directory?).with(file).and_return(false)
      expect(cli).to receive(:require).with(File.expand_path(file))
      cli.send(:require_files, file)
    end

    it "does nothing when path is nil" do
      expect(cli).not_to receive(:require)
      cli.send(:require_files, nil)
    end
  end

  describe "#options_parser (private)" do
    it "returns parser for jobs command" do
      options = {}
      parser = cli.send(:options_parser, "jobs", options)
      expect(parser).to be_a(OptionParser)
    end

    it "returns parser for streams command" do
      options = {}
      parser = cli.send(:options_parser, "streams", options)
      expect(parser).to be_a(OptionParser)
    end

    it "returns parser for actions command" do
      options = {}
      parser = cli.send(:options_parser, "actions", options)
      expect(parser).to be_a(OptionParser)
    end

    it "returns nil for unknown command" do
      options = {}
      parser = cli.send(:options_parser, "unknown", options)
      expect(parser).to be_nil
    end
  end

  describe ".banner" do
    it "returns ASCII art banner" do
      banner = described_class.banner
      expect(banner).to be_a(String)
      expect(banner).not_to be_empty
    end
  end
end
