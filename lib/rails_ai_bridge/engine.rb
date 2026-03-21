# frozen_string_literal: true

module RailsAiBridge
  class Engine < ::Rails::Engine
    # Register the MCP server after Rails finishes loading
    initializer "rails_ai_bridge.setup", after: :load_config_initializers do |_app|
      # Make introspection available via Rails console
      Rails.application.config.rails_ai_bridge = RailsAiBridge.configuration
    end

    # Auto-mount MCP HTTP middleware when configured
    initializer "rails_ai_bridge.middleware" do |app|
      RailsAiBridge.validate_auto_mount_configuration!

      if RailsAiBridge.configuration.auto_mount
        require_relative "middleware"
        app.middleware.use RailsAiBridge::Middleware
      end
    end

    # Register Rake tasks
    rake_tasks do
      load File.expand_path("tasks/rails_ai_bridge.rake", __dir__)
    end

    # Register generators
    generators do
      require_relative "../generators/rails_ai_bridge/install/install_generator"
    end
  end
end
