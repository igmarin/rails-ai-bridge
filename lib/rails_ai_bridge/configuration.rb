# frozen_string_literal: true

module RailsAiBridge
  class Configuration
    PRESETS = {
      standard: %i[schema models routes jobs gems conventions controllers tests migrations],
      full: %i[schema models routes jobs gems conventions stimulus controllers views turbo
               i18n config active_storage action_text auth api tests rake_tasks assets
               devops action_mailbox migrations seeds middleware engines multi_database]
    }.freeze

    # MCP server settings
    attr_accessor :server_name, :server_version

    # Which introspectors to run
    attr_accessor :introspectors

    # Paths to exclude from code search
    attr_accessor :excluded_paths

    # Whether to auto-mount the MCP HTTP endpoint
    attr_accessor :auto_mount

    # Allow +auto_mount+ in production (default: false). Requires a non-empty MCP token.
    attr_accessor :allow_auto_mount_in_production

    # Bearer token for HTTP MCP (+Authorization: Bearer+). Ignored when blank (no auth).
    # +ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]+ overrides this when set.
    attr_accessor :http_mcp_token

    # HTTP transport settings
    attr_accessor :http_path, :http_bind, :http_port

    # Output directory for generated context files
    attr_accessor :output_dir

    # Models/tables to exclude from introspection
    attr_accessor :excluded_models

    # TTL in seconds for cached introspection (default: 30)
    attr_accessor :cache_ttl

    # Context file generation mode
    # :compact — ≤150 lines CLAUDE.md, references MCP tools for details (default)
    # :full    — current behavior, dumps everything into context files
    attr_accessor :context_mode

    # Max lines for generated CLAUDE.md (only applies in :compact mode)
    attr_accessor :claude_max_lines

    # Max characters for any single MCP tool response (safety net)
    attr_accessor :max_tool_response_chars

    # Optional markdown merged into Copilot / Codex compact output (+config/rails_ai_bridge/overrides.md+ when +nil+)
    attr_accessor :assistant_overrides_path

    # Max model names listed in compact Copilot instructions (0 = MCP pointer only)
    attr_accessor :copilot_compact_model_list_limit

    # Max model names in compact AGENTS.md (0 = MCP pointer only)
    attr_accessor :codex_compact_model_list_limit

    # Extra file extensions allowed for +rails_search_code+ (+file_type+), merged with the gem default allowlist
    attr_accessor :search_code_allowed_file_types

    # When true, +credentials_keys+ appears in config introspection / +rails://config+ resource
    attr_accessor :expose_credentials_key_names

    # Optional custom introspectors keyed by symbol name.
    attr_accessor :additional_introspectors

    # Optional custom MCP tools appended to the built-in tool list.
    attr_accessor :additional_tools

    # Optional custom MCP resources merged with built-in resources.
    attr_accessor :additional_resources

    def initialize
      @server_name         = "rails-ai-bridge"
      @server_version      = RailsAiBridge::VERSION
      @introspectors       = PRESETS[:standard].dup
      @excluded_paths      = %w[node_modules tmp log vendor .git]
      @auto_mount          = false
      @allow_auto_mount_in_production = false
      @http_mcp_token      = nil
      @http_path           = "/mcp"
      @http_bind           = "127.0.0.1"
      @http_port           = 6029
      @output_dir          = nil # defaults to Rails.root
      @excluded_models     = %w[
        ApplicationRecord
        ActiveStorage::Blob ActiveStorage::Attachment ActiveStorage::VariantRecord
        ActionText::RichText ActionText::EncryptedRichText
        ActionMailbox::InboundEmail ActionMailbox::Record
      ]
      @cache_ttl                = 30
      @context_mode             = :compact
      @claude_max_lines         = 150
      @max_tool_response_chars  = 120_000
      @assistant_overrides_path = nil
      @copilot_compact_model_list_limit = 5
      @codex_compact_model_list_limit   = 3
      @search_code_allowed_file_types   = []
      @expose_credentials_key_names     = false
      @additional_introspectors         = {}
      @additional_tools                 = []
      @additional_resources             = {}
    end

    def preset=(name)
      name = name.to_sym
      raise ArgumentError, "Unknown preset: #{name}. Valid presets: #{PRESETS.keys.join(", ")}" unless PRESETS.key?(name)
      @introspectors = PRESETS[name].dup
    end

    def output_dir_for(app)
      @output_dir || app.root.to_s
    end
  end
end
