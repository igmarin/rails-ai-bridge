# frozen_string_literal: true

require "forwardable"

module RailsAiBridge
  # Facade that composes five config sub-objects and exposes a flat DSL.
  #
  # All attributes remain accessible directly on this object for backward
  # compatibility. Callers that need only one concern can receive the sub-object
  # via +#auth+, +#server+, +#introspection+, +#output+, or +#mcp+.
  #
  # Flat delegators are provided for the most commonly set attributes on each
  # sub-object. Less-common attributes (e.g. +mcp.mode+, +mcp.authorize+) are
  # only accessible via the sub-object directly, keeping the top-level DSL clean.
  #
  # @see Config::Auth
  # @see Config::Server
  # @see Config::Introspection
  # @see Config::Output
  # @see Config::Mcp
  # @see RailsAiBridge.configure
  class Configuration
    extend Forwardable

    PRESETS = {
      standard: %i[schema models routes jobs gems conventions controllers tests migrations],
      full: %i[schema models routes jobs gems conventions stimulus controllers views turbo
               i18n config active_storage action_text auth api tests rake_tasks assets
               devops action_mailbox migrations seeds middleware engines multi_database],
      regulated: %i[routes jobs gems conventions controllers tests]
    }.freeze

    INTROSPECTION_CATEGORY_INTROSPECTORS = {
      domain_metadata: %i[schema models migrations],
      api_surface: %i[api],
      ui_stack: %i[views stimulus turbo i18n]
    }.freeze

    # @return [Config::Auth]
    attr_reader :auth

    # @return [Config::Server]
    attr_reader :server

    # @return [Config::Introspection]
    attr_reader :introspection

    # @return [Config::Output]
    attr_reader :output

    # @return [Config::Mcp]
    attr_reader :mcp

    def initialize
      @auth          = Config::Auth.new
      @server        = Config::Server.new
      @introspection = Config::Introspection.new
      @output        = Config::Output.new
      @mcp           = Config::Mcp.new
    end

    # -- Config::Auth -----------------------------------------------------------
    def_delegators :@auth,
      :http_mcp_token, :http_mcp_token=,
      :allow_auto_mount_in_production, :allow_auto_mount_in_production=,
      :mcp_token_resolver, :mcp_token_resolver=,
      :mcp_jwt_decoder, :mcp_jwt_decoder=

    # -- Config::Server ---------------------------------------------------------
    def_delegators :@server,
      :server_name, :server_name=,
      :server_version, :server_version=,
      :http_path, :http_path=,
      :http_bind, :http_bind=,
      :http_port, :http_port=,
      :auto_mount, :auto_mount=,
      :additional_tools, :additional_tools=,
      :additional_resources, :additional_resources=

    # -- Config::Introspection --------------------------------------------------
    def_delegators :@introspection,
      :introspectors, :introspectors=,
      :excluded_paths, :excluded_paths=,
      :excluded_models, :excluded_models=,
      :excluded_tables, :excluded_tables=,
      :disabled_introspection_categories, :disabled_introspection_categories=,
      :cache_ttl, :cache_ttl=,
      :expose_credentials_key_names, :expose_credentials_key_names=,
      :additional_introspectors, :additional_introspectors=,
      :search_code_allowed_file_types, :search_code_allowed_file_types=,
      :search_code_pattern_max_bytes, :search_code_pattern_max_bytes=,
      :search_code_timeout_seconds, :search_code_timeout_seconds=,
      :preset=,
      :effective_introspectors,
      :excluded_table?

    # -- Config::Mcp ------------------------------------------------------------
    def_delegators :@mcp,
      :rate_limit_max_requests, :rate_limit_max_requests=,
      :rate_limit_window_seconds, :rate_limit_window_seconds=,
      :http_log_json, :http_log_json=,
      :require_http_auth, :require_http_auth=

    # -- Config::Output ---------------------------------------------------------
    def_delegators :@output,
      :output_dir, :output_dir=,
      :context_mode, :context_mode=,
      :claude_max_lines, :claude_max_lines=,
      :max_tool_response_chars, :max_tool_response_chars=,
      :assistant_overrides_path, :assistant_overrides_path=,
      :copilot_compact_model_list_limit, :copilot_compact_model_list_limit=,
      :codex_compact_model_list_limit, :codex_compact_model_list_limit=,
      :output_dir_for
  end
end
