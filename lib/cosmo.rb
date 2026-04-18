# frozen_string_literal: true

require "cosmo/utils"
require "cosmo/client"
require "cosmo/publisher"
require "cosmo/processor"
require "cosmo/version"
require "cosmo/config"
require "cosmo/logger"
require "cosmo/job"
require "cosmo/stream"
require "cosmo/cli"
require "cosmo/engine"
require "cosmo/api"

module Cosmo
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
end
