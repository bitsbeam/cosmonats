# frozen_string_literal: true

require "cosmo/utils/hash"
require "cosmo/utils/json"
require "cosmo/utils/string"
require "cosmo/utils/signal"
require "cosmo/utils/thread_pool"

require "cosmo/client"
require "cosmo/engine"
require "cosmo/publisher"
require "cosmo/version"
require "cosmo/config"
require "cosmo/job"
require "cosmo/stream"
require "cosmo/cli"

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
