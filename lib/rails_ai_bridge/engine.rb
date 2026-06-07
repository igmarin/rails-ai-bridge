# frozen_string_literal: true

module RailsAiBridge
  # Rails Engine that integrates +rails-ai-bridge+ into the host application.
  #
  # Registers two initializers that run as part of the normal Rails boot
  # sequence:
  #
  # * +rails_ai_bridge.setup+ — exposes {RailsAiBridge.configuration} on
  #   +Rails.application.config.rails_ai_bridge+ and, when
  #   {Configuration#cache_warm_on_boot} is enabled, schedules a
  #   {CacheWarmer.warm} call via +after_initialize+.
  # * +rails_ai_bridge.middleware+ — validates the auto-mount configuration
  #   and, when {Configuration#auto_mount} is +true+, inserts
  #   {Middleware} into the Rack stack.
  #
  # The engine also defines a +rake_tasks+ block (loads
  # +tasks/rails_ai_bridge.rake+) and a +generators+ block (loads the
  # {RailsAiBridge::Generators::InstallGenerator}).
  class Engine < ::Rails::Engine
    # Register the MCP server after Rails finishes loading
    initializer 'rails_ai_bridge.setup', after: :load_config_initializers do |app|
      # Make introspection available via Rails console
      Rails.application.config.rails_ai_bridge = RailsAiBridge.configuration

      # Pre-populate introspection cache on boot when configured
      if RailsAiBridge.configuration.cache_warm_on_boot
        app.config.after_initialize do
          CacheWarmer.warm(app)
        end
      end
    end

    # Invalidate the registry resolver cache on each code reload in development.
    #
    # +to_prepare+ fires once in production (after eager load) and on every
    # Zeitwerk reload in development. Discarding the cached resolver ensures
    # the next MCP tool call rebuilds it with the current configuration,
    # preventing stale config after an initializer change.
    config.to_prepare do
      RailsAiBridge::Registry.invalidate_resolver_cache!
    end

    # Auto-mount MCP HTTP middleware when configured
    initializer 'rails_ai_bridge.middleware' do |app|
      RailsAiBridge.validate_auto_mount_configuration!

      if RailsAiBridge.configuration.auto_mount
        require_relative 'middleware'
        app.middleware.use RailsAiBridge::Middleware
      end
    end

    # Register Rake tasks
    rake_tasks do
      load File.expand_path('tasks/rails_ai_bridge.rake', __dir__)
    end

    # Register generators
    generators do
      require_relative '../generators/rails_ai_bridge/install/install_generator'
    end
  end
end
