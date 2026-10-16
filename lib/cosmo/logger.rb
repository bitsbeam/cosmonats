# frozen_string_literal: true

require "logger"
require "forwardable"

module Cosmo
  module Logger
    TRACE = -1 # Below DEBUG; opt in with COSMO_LOG_LEVEL=trace for high-frequency polling/loop noise

    module Context
      KEY = :cosmo_context

      # Merges +options+ into the current thread's log context, restoring the previous one after the block when given.
      #
      # @param options [Hash]
      # @yieldreturn [Object]
      # @return [Object, nil] the block's result
      def self.with(**options)
        prev = current
        Thread.current[KEY] = prev.merge(options)
        yield if block_given?
      ensure
        Thread.current[KEY] = prev if block_given?
      end

      # Removes +keys+ from the current thread's log context.
      #
      # @param keys [Array<Symbol>]
      # @return [nil]
      def self.without(*keys)
        Thread.current[KEY] = current.except(*keys)
        nil
      end

      # @return [Hash] the current thread's log context
      def self.current
        Thread.current[KEY] ||= {}
        Thread.current[KEY]
      end
    end

    class BaseFormatter < ::Logger::Formatter
      # @return [String] the current thread's id, in base 36
      def tid
        (Thread.current.object_id ^ pid).to_s(36)
      end

      # @return [Integer]
      def pid
        ::Process.pid
      end
    end

    class SimpleFormatter < BaseFormatter
      # @param severity [String]
      # @param time [Time]
      # @param _ [String, nil] the progname, unused
      # @param msg [String, Exception, Object]
      # @return [String] the line, with the current {Context}
      def call(severity, time, _, msg)
        options = Context.current.compact.map { |k, v| "#{k}=#{v}" }.join(" ")
        options &&= " #{options}" unless options.empty?
        "#{time.utc.iso8601(3)} #{severity} pid=#{pid} tid=#{tid}#{options}: #{msg2str(msg)}\n"
      end
    end

    # Adds TRACE (below DEBUG) on top of stdlib's fixed DEBUG..UNKNOWN severities.
    class Instance < ::Logger
      # Logs at TRACE.
      #
      # @param progname [String, nil]
      # @yieldreturn [String] the message, built only when TRACE is enabled
      # @return [true]
      def trace(progname = nil, &)
        add(TRACE, nil, progname, &)
      end

      # @param severity [Integer]
      # @return [String]
      def format_severity(severity)
        severity == TRACE ? "TRACE" : super
      end
    end

    class << self
      extend Forwardable

      delegate %i[info error debug warn fatal] => :instance
    end

    # Dropped when the logger has no TRACE level (a plain +::Logger+), rather than flooding its DEBUG.
    #
    # @return [void]
    def self.trace(...)
      instance.trace(...) if instance.respond_to?(:trace)
    end

    # Same as {Context.with}.
    #
    # @return [Object, nil]
    def self.with(...)
      Context.with(...)
    end

    # Same as {Context.without}.
    #
    # @return [nil]
    def self.without(...)
      Context.without(...)
    end

    # @return [::Logger] the logger Cosmo writes to, stdout by default
    def self.instance
      @instance ||= Instance.new($stdout).tap do |logger|
        logger.formatter = SimpleFormatter.new
        logger.level = coerce_level(ENV.fetch("COSMO_LOG_LEVEL", "info"))
      end
    end

    # @param level [Symbol, String, Integer]
    # @return [Integer] the severity, {TRACE} included
    def self.coerce_level(level)
      level.to_s.downcase == "trace" ? TRACE : ::Logger::Severity.coerce(level)
    end

    # @param logger [::Logger] any stdlib-compatible logger. Its formatter is left alone, so context such as
    #   +jid+ and +elapsed+ is only printed when it uses {SimpleFormatter}.
    # @return [void]
    def self.instance=(logger)
      @instance = logger
    end

    # +COSMO_LOG_LEVEL+, when set, wins over +level+.
    #
    # @param level [Symbol, String, Integer] +:trace+, +:debug+, +:info+, +:warn+, +:error+, or +:fatal+
    # @return [void]
    def self.level=(level)
      instance.level = coerce_level(ENV.fetch("COSMO_LOG_LEVEL", level))
    end
  end
end
