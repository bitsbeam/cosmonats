# frozen_string_literal: true

require "yaml"
require "forwardable"
require "cosmo/config/settings"

module Cosmo
  class Config < ::Hash
    NANO = 1_000_000_000
    DEFAULT_PATH = "config/cosmo.yml"
    DEFAULTS_FILE = File.expand_path(DEFAULT_PATH, __dir__)
    SERVICE_STREAMS = %i[scheduled dead].freeze

    class << self
      extend Forwardable

      delegate %i[[] fetch dig load server_middleware client_middleware error_handlers replicas scheduled dead batches] => :instance
    end

    def self.to_ns(seconds)
      (seconds.to_f * NANO).to_i
    end

    def self.read(path)
      Utils::Hash.symbolize_keys!(YAML.load_file(path, aliases: true) || {})
    end

    def self.parse_file(path)
      read(path).tap { normalize!(_1) }
    end

    # The built-in {DEFAULTS_FILE} with +user+ deep-merged over it. Job streams are the one list that is not merged:
    # a user who lists any in +setup.jobs+ gets exactly those, and the built-in +default+ stream and consumer go away.
    # Without +setup.jobs+, +consumers.jobs.default+ still tunes the built-in consumer.
    #
    # @param user [Hash] a parsed config file, not yet normalized
    # @return [Hash] the normalized effective config
    # @raise [ConfigError] when +user+ configures something Cosmo.configure owns
    def self.build(user)
      validate!(user)
      defaults = read(DEFAULTS_FILE)
      if user.dig(:setup, :jobs)
        defaults[:setup].delete(:jobs)
        defaults[:consumers].delete(:jobs)
      end
      Utils::Hash.deep_merge(defaults, user).tap { normalize!(_1) }
    end

    def self.validate!(config)
      %i[setup consumers].each do |section|
        jobs = config.dig(section, :jobs)
        name = SERVICE_STREAMS.find { jobs.is_a?(::Hash) && jobs.key?(_1) }
        next unless name

        raise ConfigError, "`#{section}.jobs.#{name}` is a Cosmo service stream: remove it from cosmo.yml " \
                           "and tune it with Cosmo.configure { |config| config.#{name} }"
      end
      return unless config.key?(:batch_expiry)

      raise ConfigError, "`batch_expiry` moved out of cosmo.yml: Cosmo.configure { |config| config.batches.expiry = ... }"
    end

    def self.normalize!(config) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      Utils::Hash.symbolize_keys!(config)

      config[:timeout] = Utils::Duration.parse(config[:timeout]) if config[:timeout]

      config[:consumers]&.each_key do |name|
        config[:consumers][name].each do |stream_name, c|
          next unless c

          c[:ack_wait] = Utils::Duration.parse(c[:ack_wait]) if c[:ack_wait]
          c[:subject] = format(c[:subject], { name: stream_name }) if c[:subject]
          c[:subjects] = c[:subjects].map { |s| format(s, name: stream_name) } if c[:subjects]
        end
      end

      config[:setup]&.each_key do |type|
        next if type == :cron

        config[:setup][type]&.each_key do |name|
          c = config[:setup][type][name]
          c[:max_age] = to_ns(Utils::Duration.parse(c[:max_age])) if c[:max_age]
          c[:duplicate_window] = to_ns(Utils::Duration.parse(c[:duplicate_window])) if c[:duplicate_window]
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

    # Replaces the contents with {.build} of the file at +path+ (or of no file), with +overrides+ merged over it, so
    # command-line flags win over the file.
    #
    # @param path [String, nil]
    # @param overrides [Hash, nil] e.g. +{ concurrency: 5 }+
    def load(path = nil, overrides: nil)
      user = path ? self.class.read(path) : {}
      replace(self.class.build(Utils::Hash.deep_merge(user, Hash(overrides))))
    end

    attr_writer :replicas

    # @return [Integer] replicas for every service stream and bucket, e.g. 3 on a NATS cluster
    def replicas
      @replicas || 1
    end

    # @return [Scheduled]
    def scheduled
      @scheduled ||= Scheduled.new(enabled: true)
    end

    # @return [Dead]
    def dead
      @dead ||= Dead.new(enabled: true, max_age: 7 * 86_400, max_msgs: 10_000, max_bytes: -1)
    end

    # @return [Batches]
    def batches
      @batches ||= Batches.new(expiry: 3 * 86_400)
    end

    # Callables given every error Cosmo rescues: failed jobs and stream batches, fetch and scheduler errors, rejected
    # messages. Each is called with +(error, context)+, +context+ being a Hash with a +:source+ (+:job+, +:stream+,
    # +:fetch+, +:scheduler+, +:reject+, +:retry_in+, +:limit+) and what is known there, e.g. a job's payload.
    #
    #   Cosmo.configure do |config|
    #     config.error_handlers << ->(error, context) { Honeybadger.notify(error, context: context) }
    #   end
    #
    # @return [Array<#call>]
    def error_handlers
      @error_handlers ||= []
    end

    # @return [::Logger] the logger Cosmo writes to, see {Logger.instance}
    def logger
      Logger.instance
    end

    # Replaces Cosmo's stdout logger, e.g. with +Rails.logger+. Give it +Cosmo::Logger::SimpleFormatter.new+ to keep
    # Cosmo's +jid+/+elapsed+ context in each line.
    #
    # @param logger [::Logger]
    def logger=(logger)
      Logger.instance = logger
    end

    # Ignored when +COSMO_LOG_LEVEL+ is set, which always wins.
    #
    # @param level [Symbol, String, Integer] +:trace+, +:debug+, +:info+, +:warn+, +:error+, or +:fatal+
    def log_level=(level)
      Logger.level = level
    end

    # The chain every job execution runs through, starting with the built-in {Middleware::Limit}, {Middleware::Busy}, and
    # {Middleware::Totals}. It lives outside the loaded YAML, so {#load} keeps it. Register middleware
    # at boot, before workers start:
    #
    #   Cosmo.configure do |config|
    #     config.server_middleware do |chain|
    #       chain.add MyMiddleware
    #     end
    #   end
    #
    # @yieldparam chain [Middleware::Chain]
    # @return [Middleware::Chain]
    def server_middleware
      @server_middleware ||= Middleware::Chain.new do |chain|
        chain.add Middleware::Limit
        chain.add Middleware::Busy
        chain.add Middleware::Totals
      end
      yield @server_middleware if block_given?
      @server_middleware
    end

    # The chain every job enqueue runs through, empty by default. A middleware is called with
    # +(job_class_name, payload, stream)+ around the publish: it may change +payload+ (the Hash that gets published),
    # or not yield to stop the publish, so +perform_async+ returns +nil+. +stream+ is the stream the job runs on.
    #
    #   Cosmo.configure do |config|
    #     config.client_middleware { |chain| chain.add RequestIdMiddleware }
    #   end
    #
    # @yieldparam chain [Middleware::Chain]
    # @return [Middleware::Chain]
    def client_middleware
      @client_middleware ||= Middleware::Chain.new
      yield @client_middleware if block_given?
      @client_middleware
    end
  end
end
