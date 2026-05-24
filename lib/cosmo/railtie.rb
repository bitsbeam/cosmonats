# frozen_string_literal: true

module Cosmo
  # Rails Railtie — loaded automatically when cosmonats is required inside a
  # Rails application. Ensures the ActiveJob adapter constant is registered
  # before Rails tries to resolve it and autoloads +config/cosmo.yml+ when
  # the file is present.
  class Railtie < ::Rails::Railtie
    # Make Cosmo::ActiveJobAdapter::Adapter available under the conventional
    # ActiveJob namespace so :cosmonats resolves without any extra requires.
    initializer "cosmo.active_job_adapter", before: :run_prepare_callbacks do
      require "cosmo/active_job"
    end

    # Autoload config/cosmo.yml when it exists and no config has been loaded yet.
    initializer "cosmo.load_config", after: "cosmo.active_job_adapter" do |app|
      config_path = app.root.join("config", "cosmo.yml")
      Config.load(config_path.to_s) if config_path.exist? && Config.instance.none?
    end
  end
end
