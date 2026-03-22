# frozen_string_literal: true

module RailsAiBridge
  # Diagnostic checker that validates the environment and reports
  # AI readiness with pass/warn/fail checks and a readiness score.
  class Doctor
    Check = Data.define(:name, :status, :message, :fix)

    CHECKS = %i[
      check_schema
      check_models
      check_routes
      check_gems
      check_controllers
      check_views
      check_i18n
      check_tests
      check_migrations
      check_context_files
      check_mcp_buildable
      check_ripgrep
      check_view_mcp_tool
      check_stimulus_mcp_tool
      check_bridge_metadata
    ].freeze

    attr_reader :app

    # @param app [Rails::Application, nil] application to inspect
    # @return [void]
    def initialize(app = nil)
      @app = app || Rails.application
    end

    # Runs all diagnostic checks and computes a readiness score.
    #
    # @return [Hash] diagnostic result with `:checks` and `:score`
    def run
      results = CHECKS.map { |check| send(check) }
      score = compute_score(results)
      { checks: results, score: score }
    end

    private

    def check_schema
      schema_path = File.join(app.root, "db/schema.rb")
      if File.exist?(schema_path)
        Check.new(name: "Schema", status: :pass, message: "db/schema.rb found", fix: nil)
      else
        Check.new(name: "Schema", status: :warn, message: "db/schema.rb not found", fix: "Run `rails db:schema:dump` to generate it")
      end
    end

    def check_models
      models_dir = File.join(app.root, "app/models")
      if Dir.exist?(models_dir) && Dir.glob(File.join(models_dir, "**/*.rb")).any?
        count = Dir.glob(File.join(models_dir, "**/*.rb")).size
        Check.new(name: "Models", status: :pass, message: "#{count} model files found", fix: nil)
      else
        Check.new(name: "Models", status: :warn, message: "No model files found in app/models/", fix: "Generate models with `rails generate model`")
      end
    end

    def check_routes
      routes_path = File.join(app.root, "config/routes.rb")
      if File.exist?(routes_path)
        Check.new(name: "Routes", status: :pass, message: "config/routes.rb found", fix: nil)
      else
        Check.new(name: "Routes", status: :fail, message: "config/routes.rb not found", fix: "Ensure you're in a Rails app root directory")
      end
    end

    def check_gems
      lock_path = File.join(app.root, "Gemfile.lock")
      if File.exist?(lock_path)
        Check.new(name: "Gems", status: :pass, message: "Gemfile.lock found", fix: nil)
      else
        Check.new(name: "Gems", status: :warn, message: "Gemfile.lock not found", fix: "Run `bundle install` to generate it")
      end
    end

    def check_controllers
      dir = File.join(app.root, "app/controllers")
      if Dir.exist?(dir) && Dir.glob(File.join(dir, "**/*.rb")).any?
        count = Dir.glob(File.join(dir, "**/*.rb")).size
        Check.new(name: "Controllers", status: :pass, message: "#{count} controller files found", fix: nil)
      else
        Check.new(name: "Controllers", status: :warn, message: "No controller files found in app/controllers/", fix: "Generate controllers with `rails generate controller`")
      end
    end

    def check_views
      dir = File.join(app.root, "app/views")
      if Dir.exist?(dir) && Dir.glob(File.join(dir, "**/*")).reject { |f| File.directory?(f) }.any?
        count = Dir.glob(File.join(dir, "**/*")).reject { |f| File.directory?(f) }.size
        Check.new(name: "Views", status: :pass, message: "#{count} view files found", fix: nil)
      else
        Check.new(name: "Views", status: :warn, message: "No view files found in app/views/", fix: "Views are generated alongside controllers")
      end
    end

    def check_i18n
      dir = File.join(app.root, "config/locales")
      if Dir.exist?(dir) && Dir.glob(File.join(dir, "**/*.{yml,yaml}")).any?
        count = Dir.glob(File.join(dir, "**/*.{yml,yaml}")).size
        Check.new(name: "I18n", status: :pass, message: "#{count} locale files found", fix: nil)
      else
        Check.new(name: "I18n", status: :warn, message: "No locale files found in config/locales/", fix: "Add locale files for internationalization support")
      end
    end

    def check_tests
      if Dir.exist?(File.join(app.root, "spec")) || Dir.exist?(File.join(app.root, "test"))
        framework = Dir.exist?(File.join(app.root, "spec")) ? "RSpec" : "Minitest"
        Check.new(name: "Tests", status: :pass, message: "#{framework} test directory found", fix: nil)
      else
        Check.new(name: "Tests", status: :warn, message: "No test directory found", fix: "Set up tests with `rails generate rspec:install` or use default Minitest")
      end
    end

    def check_migrations
      migrate_dir = File.join(app.root, "db/migrate")
      if Dir.exist?(migrate_dir) && Dir.glob(File.join(migrate_dir, "*.rb")).any?
        count = Dir.glob(File.join(migrate_dir, "*.rb")).size
        Check.new(name: "Migrations", status: :pass, message: "#{count} migration files found", fix: nil)
      else
        Check.new(name: "Migrations", status: :warn, message: "No migrations found in db/migrate/", fix: "Run `rails generate migration` to create one")
      end
    end

    def check_context_files
      claude_path = File.join(app.root, "CLAUDE.md")
      if File.exist?(claude_path)
        Check.new(name: "Bridge files", status: :pass, message: "CLAUDE.md exists", fix: nil)
      else
        Check.new(name: "Bridge files", status: :warn, message: "No bridge files generated yet", fix: "Run `rails ai:bridge` to generate them")
      end
    end

    def check_mcp_buildable
      Server.new(app).build
      Check.new(name: "MCP server", status: :pass, message: "MCP server builds successfully", fix: nil)
    rescue => e
      Check.new(name: "MCP server", status: :fail, message: "MCP server failed to build: #{e.message}", fix: "Check mcp gem installation: `bundle info mcp`")
    end

    def check_ripgrep
      if system("which rg > /dev/null 2>&1")
        Check.new(name: "ripgrep", status: :pass, message: "rg available for code search", fix: nil)
      else
        Check.new(name: "ripgrep", status: :warn, message: "ripgrep not installed (code search will use slower Ruby fallback)", fix: "Install with `brew install ripgrep` or `apt install ripgrep`")
      end
    end

    def check_view_mcp_tool
      return Check.new(name: "View MCP tool", status: :pass, message: "No view files detected; view MCP tool not required", fix: nil) unless view_files_present?

      unless RailsAiBridge.configuration.introspectors.include?(:views)
        return Check.new(
          name: "View MCP tool",
          status: :warn,
          message: "Views detected but :views introspector is disabled",
          fix: "Enable it with `RailsAiBridge.configure { |c| c.introspectors |= [:views] }`"
        )
      end

      if tool_registered?("rails_get_view")
        Check.new(name: "View MCP tool", status: :pass, message: "rails_get_view available for view inspection", fix: nil)
      else
        Check.new(name: "View MCP tool", status: :fail, message: "rails_get_view is not registered", fix: "Register `RailsAiBridge::Tools::GetView` in the MCP server")
      end
    end

    def check_stimulus_mcp_tool
      return Check.new(name: "Stimulus MCP tool", status: :pass, message: "No Stimulus controllers detected; stimulus MCP tool not required", fix: nil) unless stimulus_files_present?

      unless RailsAiBridge.configuration.introspectors.include?(:stimulus)
        return Check.new(
          name: "Stimulus MCP tool",
          status: :warn,
          message: "Stimulus controllers detected but :stimulus introspector is disabled",
          fix: "Enable it with `RailsAiBridge.configure { |c| c.introspectors |= [:stimulus] }`"
        )
      end

      if tool_registered?("rails_get_stimulus")
        Check.new(name: "Stimulus MCP tool", status: :pass, message: "rails_get_stimulus available for Hotwire UI inspection", fix: nil)
      else
        Check.new(name: "Stimulus MCP tool", status: :fail, message: "rails_get_stimulus is not registered", fix: "Register `RailsAiBridge::Tools::GetStimulus` in the MCP server")
      end
    end

    def check_bridge_metadata
      if RailsAiBridge::Resources.resource_definitions.key?("rails://bridge/meta")
        Check.new(name: "Bridge metadata", status: :pass, message: "rails://bridge/meta available for bridge diagnostics", fix: nil)
      else
        Check.new(name: "Bridge metadata", status: :fail, message: "rails://bridge/meta resource is missing", fix: "Register the bridge metadata resource in `RailsAiBridge::Resources`")
      end
    end

    def compute_score(results)
      total = results.size * 10
      earned = results.sum do |check|
        case check.status
        when :pass then 10
        when :warn then 5
        else 0
        end
      end
      ((earned.to_f / total) * 100).round
    end

    def tool_registered?(tool_name)
      (RailsAiBridge::Server::TOOLS + RailsAiBridge.configuration.additional_tools).any? { |tool| tool.tool_name == tool_name }
    end

    def view_files_present?
      dir = File.join(app.root, "app/views")
      Dir.exist?(dir) && Dir.glob(File.join(dir, "**/*")).reject { |path| File.directory?(path) }.any?
    end

    def stimulus_files_present?
      dir = File.join(app.root, "app/javascript/controllers")
      Dir.exist?(dir) && Dir.glob(File.join(dir, "**/*_controller.{js,ts}")).any?
    end
  end
end
