# frozen_string_literal: true

require "logger"
require "forwardable"

module Cosmo
  module Logger
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

    class << self
      extend Forwardable

      delegate %i[info error debug warn fatal] => :instance
    end

    def self.with(...)
      Context.with(...)
    end

    def self.without(...)
      Context.without(...)
    end

    def self.instance
      @instance ||= ::Logger.new($stdout).tap { it.formatter = SimpleFormatter.new }
    end
  end
end
