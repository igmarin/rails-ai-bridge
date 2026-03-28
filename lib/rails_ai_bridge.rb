# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.inflector.inflect("devops_introspector" => "DevOpsIntrospector")
loader.ignore("#{__dir__}/generators")
loader.ignore("#{__dir__}/rails-ai-bridge.rb")
loader.setup

module RailsAiBridge
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class IntrospectionError < Error; end

  class << self
    # Global configuration
    attr_writer :configuration

    # Returns the mutable gem configuration object.
    #
    # @return [RailsAiBridge::Configuration] current configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Yields the global configuration for mutation.
    #
    # @yieldparam configuration [RailsAiBridge::Configuration] mutable config object
    # @return [void]
    def configure
      yield(configuration)
    end

    # Quick access to introspect the current Rails app
    # Returns a hash of all discovered context.
    #
    # @param app [Rails::Application, nil] app to introspect, defaults to Rails.application
    # @param only [Array<Symbol>, nil] optional subset of introspector keys to run
    # @return [Hash] introspection payload with enabled sections
    def introspect(app = nil, only: nil)
      app ||= Rails.application
      Introspector.new(app).call(only: only)
    end

    # Generate context files (CLAUDE.md, .cursorrules, etc.)
    #
    # @param app [Rails::Application, nil] app to introspect, defaults to Rails.application
    # @param format [Symbol, Array<Symbol>] output format (+:all+, +:install+, +:claude+, …, or an array from install.yml)
    # @return [Hash{Symbol => Array<String>}] files grouped under +:written+ and +:skipped+
    def generate_context(app = nil, format: :all)
      app ||= Rails.application
      warn_stubbed_assistant_overrides
      context = introspect(app)
      Serializers::ContextFileSerializer.new(context, format: resolve_generate_format(format)).call
    end

    # @param format [Object]
    # @return [Symbol, Array<Symbol>]
    def resolve_generate_format(format)
      case format
      when :install
        prefs = AssistantFormatsPreference.formats_for_default_bridge_task
        prefs.nil? ? :all : prefs
      else
        format
      end
    end

    # @return [void]
    def warn_stubbed_assistant_overrides
      return unless Serializers::SharedAssistantGuidance.overrides_stub_active?

      warn "[rails-ai-bridge] config/rails_ai_bridge/overrides.md is still the install stub (remove the first-line " \
           "<!-- rails-ai-bridge:omit-merge --> marker so team rules merge into Copilot/Codex output)."
    end

    # Start the MCP server programmatically
    #
    # @param app [Rails::Application, nil] app to serve, defaults to Rails.application
    # @param transport [Symbol] transport type (:stdio or :http)
    # @return [void]
    # @raise [RailsAiBridge::ConfigurationError] when HTTP transport is unsafe in production
    def start_mcp_server(app = nil, transport: :stdio)
      app ||= Rails.application
      Server.new(app, transport: transport).start
    end

    # Raises {ConfigurationError} if +auto_mount+ is enabled in production without explicit opt-in and token.
    #
    # @return [void]
    # @raise [RailsAiBridge::ConfigurationError] when production auto-mount safety requirements are not met
    def validate_auto_mount_configuration!
      cfg = configuration
      return unless cfg.auto_mount
      return unless Rails.env.production?

      unless cfg.allow_auto_mount_in_production
        raise ConfigurationError,
              "rails_ai_bridge: auto_mount is disabled in production unless you set allow_auto_mount_in_production = true"
      end

      return if mcp_auth_mechanism_configured?

      raise ConfigurationError,
            "rails_ai_bridge: auto_mount in production requires http_mcp_token or ENV['#{McpHttpAuth::TOKEN_ENV_KEY}'], " \
            "config.mcp.auth.token_resolver, or config.mcp.auth.jwt_decoder"
    end

    # Raises {ConfigurationError} when starting the standalone HTTP MCP server in production without a token.
    #
    # @return [void]
    # @raise [RailsAiBridge::ConfigurationError] when production HTTP MCP starts without a token
    def validate_http_mcp_server_in_production!
      return unless Rails.env.production?
      return if mcp_auth_mechanism_configured?

      raise ConfigurationError,
            "rails_ai_bridge: HTTP MCP in production requires http_mcp_token or ENV['#{McpHttpAuth::TOKEN_ENV_KEY}'], " \
            "config.mcp.auth.token_resolver, or config.mcp.auth.jwt_decoder"
    end

    # True when static MCP token, +token_resolver+, or +jwt_decoder+ is configured.
    #
    # @return [Boolean]
    def mcp_auth_mechanism_configured?
      McpHttpAuth.http_mcp_auth_configured? ||
        configuration.mcp.auth.token_resolver.present? ||
        configuration.mcp.auth.jwt_decoder.present?
    end

    # Raises when +strategy == :bearer_token+ but neither +token_resolver+ nor static MCP token is configured.
    #
    # @return [void]
    # @raise [RailsAiBridge::ConfigurationError]
    def validate_mcp_strategy_configuration!
      a = configuration.mcp.auth
      return unless a.strategy == :bearer_token
      return if a.token_resolver.present?
      return if McpHttpAuth.http_mcp_auth_configured?

      raise ConfigurationError,
            "rails_ai_bridge: strategy :bearer_token requires config.mcp.auth.token_resolver or " \
            "http_mcp_token / ENV['#{McpHttpAuth::TOKEN_ENV_KEY}']. Otherwise HTTP MCP would be unauthenticated. See UPGRADING.md."
    end

    # Raises when +config.mcp.require_auth_in_production+ is +true+ in production and no MCP auth mechanism exists.
    #
    # @return [void]
    # @raise [RailsAiBridge::ConfigurationError]
    def validate_mcp_require_auth_in_production!
      return unless Rails.env.production?
      return unless configuration.mcp.require_auth_in_production
      return if mcp_auth_mechanism_configured?

      raise ConfigurationError,
            "rails_ai_bridge: MCP auth cannot be disabled in production (require_auth_in_production is true). " \
            "Set http_mcp_token, ENV['#{McpHttpAuth::TOKEN_ENV_KEY}'], config.mcp.auth.token_resolver, or " \
            "config.mcp.auth.jwt_decoder. See UPGRADING.md."
    end
  end
end

# Rails integration — loaded by Bundler.require after Rails is booted
require_relative "rails_ai_bridge/engine" if defined?(Rails::Engine)
