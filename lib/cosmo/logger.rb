# frozen_string_literal: true

require "logger"
require "forwardable"

module Cosmo
  module Logger
    TRACE = -1 # Below DEBUG; opt in with COSMO_LOG_LEVEL=trace for high-frequency polling/loop noise

    module Context
      KEY = :cosmo_context

      def self.with(**options)
        prev = current
        Thread.current[KEY] = prev.merge(options)
        yield if block_given?
      ensure
        Thread.current[KEY] = prev if block_given?
      end

      def self.without(*keys)
        Thread.current[KEY] = current.except(*keys)
        nil
      end

      def self.current
        Thread.current[KEY] ||= {}
        Thread.current[KEY]
      end
    end

    class BaseFormatter < ::Logger::Formatter
      def tid
        (Thread.current.object_id ^ pid).to_s(36)
      end

      def pid
        ::Process.pid
      end
    end

    class SimpleFormatter < BaseFormatter
      def call(severity, time, _, msg)
        options = Context.current.compact.map { |k, v| "#{k}=#{v}" }.join(" ")
        options &&= " #{options}" unless options.empty?
        "#{time.utc.iso8601(3)} #{severity} pid=#{pid} tid=#{tid}#{options}: #{msg2str(msg)}\n"
      end
    end

    # Adds TRACE (below DEBUG) on top of stdlib's fixed DEBUG..UNKNOWN severities.
    class Instance < ::Logger
      def trace(progname = nil, &)
        add(TRACE, nil, progname, &)
      end

      def format_severity(severity)
        severity == TRACE ? "TRACE" : super
      end
    end

    class << self
      extend Forwardable

      delegate %i[info error debug warn fatal] => :instance
    end

    # Dropped when the logger has no TRACE level (a plain +::Logger+), rather than flooding its DEBUG.
    def self.trace(...)
      instance.trace(...) if instance.respond_to?(:trace)
    end

    def self.with(...)
      Context.with(...)
    end

    def self.without(...)
      Context.without(...)
    end

    def self.instance
      @instance ||= Instance.new($stdout).tap do |logger|
        logger.formatter = SimpleFormatter.new
        logger.level = coerce_level(ENV.fetch("COSMO_LOG_LEVEL", "info"))
      end
    end

    def self.coerce_level(level)
      level.to_s.downcase == "trace" ? TRACE : ::Logger::Severity.coerce(level)
    end

    # @param logger [::Logger] any stdlib-compatible logger. Its formatter is left alone, so context such as
    #   +jid+ and +elapsed+ is only printed when it uses {SimpleFormatter}.
    def self.instance=(logger)
      @instance = logger
    end

    # +COSMO_LOG_LEVEL+, when set, wins over +level+.
    #
    # @param level [Symbol, String, Integer] +:trace+, +:debug+, +:info+, +:warn+, +:error+, or +:fatal+
    def self.level=(level)
      instance.level = coerce_level(ENV.fetch("COSMO_LOG_LEVEL", level))
    end
  end
end
