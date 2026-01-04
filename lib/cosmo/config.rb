# frozen_string_literal: true

require "yaml"
require "forwardable"

module Cosmo
  class Config
    NANO = 1_000_000_000
    DEFAULT_PATH = "config/cosmo.yml"

    class << self
      extend Forwardable

      delegate %i[[] fetch dig to_h set load] => :instance
    end

    def self.parse_file(path)
      YAML.load_file(path, aliases: true).tap { normalize!(_1) }
    end

    def self.normalize!(config)
      Utils::Hash.symbolize_keys!(config)

      config[:consumers]&.each_key do |name|
        config[:consumers][name].each do |stream_name, c|
          next unless c

          c[:subject] = format(c[:subject], { name: stream_name }) if c[:subject]
          c[:subjects] = c[:subjects].map { |s| format(s, name: stream_name) } if c[:subjects]
        end
      end

      config[:streams]&.each_key do |name|
        c = config[:streams][name]
        c[:max_age] = c[:max_age].to_i * NANO if c[:max_age]
        c[:duplicate_window] = c[:duplicate_window].to_i * NANO if c[:duplicate_window]
        c[:subjects] = c[:subjects].map { |s| format(s, name: name) } if c[:subjects]
      end
    end

    def self.instance
      @instance ||= new
    end

    def self.system
      @system ||= {}
    end

    def initialize
      @config = nil
      @system = {}
      @defaults = self.class.parse_file(File.expand_path("defaults.yml", __dir__))
    end

    def [](key)
      dig(key)
    end

    def fetch(key, default = nil)
      return @config.fetch(key, default) if @config && Utils::Hash.keys?(@config, key)

      @defaults.fetch(key, default)
    end

    def dig(*keys)
      return @config&.dig(*keys) if @config && Utils::Hash.keys?(@config, *keys)

      @defaults&.dig(*keys)
    end

    def to_h
      Utils::Hash.merge(@defaults, @config)
    end

    def set(...)
      Utils::Hash.set(@config, ...)
    end

    def load(path = nil)
      return unless path

      @config = self.class.parse_file(path)
    end
  end
end
