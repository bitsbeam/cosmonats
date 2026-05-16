# frozen_string_literal: true

require "yaml"
require "forwardable"

module Cosmo
  class Config < ::Hash
    NANO = 1_000_000_000
    DEFAULT_PATH = "config/cosmo.yml"

    class << self
      extend Forwardable

      delegate %i[[] fetch dig to_h set load] => :instance
    end

    def self.parse_file(path)
      YAML.load_file(path, aliases: true).tap { normalize!(_1) }
    end

    def self.normalize!(config) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      Utils::Hash.symbolize_keys!(config)

      config[:consumers]&.each_key do |name|
        config[:consumers][name].each do |stream_name, c|
          next unless c

          c[:subject] = format(c[:subject], { name: stream_name }) if c[:subject]
          c[:subjects] = c[:subjects].map { |s| format(s, name: stream_name) } if c[:subjects]
        end
      end

      config[:setup]&.each_key do |type|
        config[:setup][type]&.each_key do |name|
          c = config[:setup][type][name]
          c[:max_age] = c[:max_age].to_i * NANO if c[:max_age]
          c[:duplicate_window] = c[:duplicate_window].to_i * NANO if c[:duplicate_window]
          c[:subjects] = c[:subjects].map { |s| format(s, name: name) } if c[:subjects]
        end
      end
    end

    def self.deliver_policy(start_position)
      case start_position
      when "last", :last
        { deliver_policy: "last" }
      when "new", :new
        { deliver_policy: "new" }
      when Time
        { deliver_policy: "by_start_time", opt_start_time: start_position.iso8601 }
      when String
        { deliver_policy: "by_start_time", opt_start_time: start_position }
      else
        { deliver_policy: "all" }
      end
    end

    def self.instance
      @instance ||= new
    end

    def self.internal
      @internal ||= {}
    end

    def set(...)
      Utils::Hash.set(self, ...)
    end

    def load(path = nil)
      return unless path

      replace(self.class.parse_file(path))
    end
  end
end
