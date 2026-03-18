# frozen_string_literal: true

module RailsAiContext
  class Engine < ::Rails::Engine
    # Register the MCP server after Rails finishes loading
    initializer "rails_ai_context.setup", after: :load_config_initializers do |_app|
      # Make introspection available via Rails console
      Rails.application.config.rails_ai_context = RailsAiContext.configuration
    end

    # Auto-mount MCP HTTP middleware when configured
    initializer "rails_ai_context.middleware" do |app|
      if RailsAiContext.configuration.auto_mount
        require_relative "middleware"
        app.middleware.use RailsAiContext::Middleware
      end
    end

    # Register Rake tasks
    rake_tasks do
      load File.expand_path("tasks/rails_ai_context.rake", __dir__)
    end

    # Register generators
    generators do
      require_relative "../generators/rails_ai_context/install/install_generator"
    end
  end
end
