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
require "cosmo/railtie" if defined?(Rails::Railtie)

module Cosmo
  # Optional, requires rack
  autoload :Web, "cosmo/web"
  # Optional, requires rack and webrick gems. Loaded only when an HTTP port is configured.
  autoload :HTTPServer, "cosmo/http_server"

  class Error < StandardError; end

  class ArgumentError < Error; end

  class NotImplementedError < Error; end

  class ConfigNotFoundError < Error
    def initialize(config_file)
      super("No such file #{config_file}")
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
