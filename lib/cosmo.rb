# frozen_string_literal: true

require "cosmo/utils"
require "cosmo/client"
require "cosmo/publisher"
require "cosmo/processor"
require "cosmo/version"
require "cosmo/config"
require "cosmo/logger"
require "cosmo/job"
require "cosmo/batch"
require "cosmo/stream"
require "cosmo/cli"
require "cosmo/heartbeat"
require "cosmo/engine"
require "cosmo/api"
require "cosmo/middleware"
require "cosmo/services"
require "cosmo/railtie" if defined?(Rails::Railtie)

module Cosmo
  # Optional, requires rack
  autoload :Web, "cosmo/web"
  # Optional, requires rack and webrick gems. Loaded only when an HTTP port is configured.
  autoload :HTTPServer, "cosmo/http_server"

  # Programmatic setup, typically from an initializer:
  #
  #   Cosmo.configure do |config|
  #     config.logger = Rails.logger
  #     config.log_level = :debug
  #     config.server_middleware { |c| c.add MyMiddleware }
  #   end
  #
  # @yieldparam config [Config] the {Config} singleton
  # @return [void]
  def self.configure
    yield Config.instance
  end

  # Hands +error+ to every handler in {Config#error_handlers}. A handler that raises is logged and skipped, so error
  # reporting never breaks processing.
  #
  # @param error [Exception]
  # @param context [Hash] where it happened, see {Config#error_handlers}
  # @return [void]
  def self.handle_error(error, context)
    Config.error_handlers.each do |handler|
      handler.call(error, context)
    rescue StandardError => e
      Logger.error "Error handler failed: #{e.class}: #{e.message}"
    end
  end

  class Error < StandardError; end

  class ArgumentError < Error; end

  class NotImplementedError < Error; end

  class ConfigError < Error; end

  class ConfigNotFoundError < Error
    def initialize(config_file)
      super("No such file #{config_file}")
    end
  end

  class SchedulingDisabledError < Error
    def initialize
      super("Scheduling is turned off (config.scheduled.enabled = false), so delayed jobs and crons are unavailable")
    end
  end

  class StreamNotFoundError < Error
    def initialize(stream_name)
      super("Missing stream `#{stream_name}`")
    end
  end

  class UnknownJobStreamError < Error
    def initialize(names, configured)
      super("Unknown job stream#{"s" if names.size > 1} #{names.map { "`#{_1}`" }.join(", ")}; " \
            "configured: #{configured.empty? ? "none" : configured.map { "`#{_1}`" }.join(", ")}")
    end
  end
end
