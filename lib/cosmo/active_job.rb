# frozen_string_literal: true

require "cosmo/active_job/options"
require "cosmo/active_job/executor"
require "cosmo/active_job/adapter"

module Cosmo
  # ActiveJob integration for Cosmonats.
  #
  # In a Rails app the Railtie (loaded via cosmonats) handles everything.
  # For standalone use:
  #
  #   require "cosmo/active_job"
  #   ActiveJob::Base.queue_adapter = Cosmo::ActiveJobAdapter::Adapter.new
  module ActiveJobAdapter
  end
end

# Register the adapter under the conventional ActiveJob name so that
# `config.active_job.queue_adapter = :cosmonats` resolves automatically.
if defined?(ActiveJob)
  ActiveJob::QueueAdapters::CosmonatsAdapter = Cosmo::ActiveJobAdapter::Adapter

  if defined?(ActiveSupport)
    ActiveSupport.on_load(:active_job) { include Cosmo::ActiveJobAdapter::Options }
  else
    ActiveJob::Base.include(Cosmo::ActiveJobAdapter::Options)
  end
end
