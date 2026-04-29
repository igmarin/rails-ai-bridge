# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.inflector.inflect('devops_introspector' => 'DevOpsIntrospector')
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
    # @param options [Hash] keyword options
    # @option options [Symbol, Array<Symbol>] :format output format(s); defaults to +:all+
    # @option options [Boolean] :split_rules whether to generate per-assistant rule directories; defaults to +true+
    # @option options [:overwrite, :skip, :prompt, #call] :on_conflict behaviour when a file exists with
    #   different content. +:overwrite+ (default) silently replaces; +:skip+ keeps the existing file;
    #   +:prompt+ asks via stdin; any callable receives the filepath and returns truthy to overwrite.
    # @return [Hash{Symbol => Array<String>}] files grouped under +:written+ and +:skipped+
    # @raise [ArgumentError] when an unknown option key is passed
    def generate_context(app = nil, **options)
      allowed = %i[format split_rules on_conflict].to_set
      unknown = options.keys.to_set - allowed
      raise ArgumentError, "Unknown option(s): #{unknown.to_a.join(', ')}" if unknown.any?

      app ||= Rails.application
      context = introspect(app)
      Serializers::ContextFileSerializer.new(context,
                                             format: options.fetch(:format, :all),
                                             split_rules: options.fetch(:split_rules, true),
                                             on_conflict: options.fetch(:on_conflict, :overwrite)).call
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
      return unless Rails.env.production? || cfg.mcp.require_auth_in_production

      unless cfg.allow_auto_mount_in_production
        raise ConfigurationError,
              'rails_ai_bridge: auto_mount is disabled in production unless you set allow_auto_mount_in_production = true'
      end

      return if Mcp::Authenticator.any_configured?

      raise ConfigurationError,
            'rails_ai_bridge: auto_mount in production requires an auth mechanism ' \
            "(http_mcp_token, mcp_token_resolver, mcp_jwt_decoder, or ENV['#{Mcp::Authenticator::TOKEN_ENV_KEY}'])"
    end

    # Raises {ConfigurationError} when starting the standalone HTTP MCP server in production without a token.
    #
    # Also enforces {Config::Mcp#require_auth_in_production} when +true+, regardless of Rails env.
    #
    # @return [void]
    # @raise [RailsAiBridge::ConfigurationError] when HTTP MCP starts without a required auth mechanism
    def validate_http_mcp_server_in_production!
      return unless Rails.env.production? || configuration.mcp.require_auth_in_production
      return if Mcp::Authenticator.any_configured?

      raise ConfigurationError,
            'rails_ai_bridge: HTTP MCP in production requires an auth mechanism ' \
            "(http_mcp_token, mcp_token_resolver, mcp_jwt_decoder, or ENV['#{Mcp::Authenticator::TOKEN_ENV_KEY}'])"
    end
  end
end

# Rails integration — loaded by Bundler.require after Rails is booted
require_relative 'rails_ai_bridge/engine' if defined?(Rails::Engine)
