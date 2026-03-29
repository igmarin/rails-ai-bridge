# frozen_string_literal: true

module RailsAiBridge
  # Holds user-facing configuration: introspector presets, exclusions (models, tables, categories),
  # MCP HTTP settings, context generation options, and extensibility hooks.
  #
  # Presets ({PRESETS}) set the base +introspectors+ list. {#disabled_introspection_categories}
  # subtracts whole product categories at runtime. {#effective_introspectors} is the final list
  # used by {Introspector} and MCP tools.
  #
  # @see RailsAiBridge.configure
  # @see Introspector
  class Configuration
    PRESETS = {
      standard: %i[schema models routes jobs gems conventions controllers tests migrations],
      full: %i[schema models routes jobs gems conventions stimulus controllers views turbo
               i18n config active_storage action_text auth api tests rake_tasks assets
               devops action_mailbox migrations seeds middleware engines multi_database],
      # Minimal surface: no schema, models, or migrations introspection (for regulated/sensitive apps).
      regulated: %i[routes jobs gems conventions controllers tests]
    }.freeze

    # Product-level categories that subtract introspectors from the active preset (see +#effective_introspectors+).
    INTROSPECTION_CATEGORY_INTROSPECTORS = {
      domain_metadata: %i[schema models migrations],
      api_surface: %i[api],
      ui_stack: %i[views stimulus turbo i18n]
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

    # Table names to skip in schema/model introspection (exact match or glob with +*+, e.g. +"secrets_*"+).
    attr_accessor :excluded_tables

    # Category keys from {INTROSPECTION_CATEGORY_INTROSPECTORS} to remove from the active preset at runtime.
    attr_accessor :disabled_introspection_categories

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

    # Lambda that resolves a raw Bearer token to an auth context (or +nil+/+false+ to deny).
    # When set, takes priority over the static +http_mcp_token+.
    #
    # @example Devise token
    #   config.mcp_token_resolver = ->(token) { User.find_by(api_token: token) }
    #
    # @return [Proc, nil]
    attr_accessor :mcp_token_resolver

    # Lambda that decodes a raw Bearer JWT to a payload hash (or +nil+/+false+ to deny).
    # No JWT gem is required — supply your own decoding logic.
    # Takes priority over both +mcp_token_resolver+ and +http_mcp_token+.
    #
    # @example Using the +jwt+ gem
    #   config.mcp_jwt_decoder = ->(token) {
    #     JWT.decode(token, Rails.application.credentials.jwt_secret, true, algorithm: "HS256").first
    #   rescue JWT::DecodeError
    #     nil
    #   }
    #
    # @return [Proc, nil]
    attr_accessor :mcp_jwt_decoder

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
      @excluded_tables                    = []
      @disabled_introspection_categories  = []
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
      @mcp_token_resolver               = nil
      @mcp_jwt_decoder                  = nil
    end

    def preset=(name)
      name = name.to_sym
      raise ArgumentError, "Unknown preset: #{name}. Valid presets: #{PRESETS.keys.join(", ")}" unless PRESETS.key?(name)
      @introspectors = PRESETS[name].dup
    end

    # Introspectors after removing any disabled by {#disabled_introspection_categories}.
    #
    # @return [Array<Symbol>]
    def effective_introspectors
      disabled = @disabled_introspection_categories.flat_map do |c|
        INTROSPECTION_CATEGORY_INTROSPECTORS[c.to_sym] || []
      end.uniq
      @introspectors.reject { |i| disabled.include?(i) }
    end

    # Whether a logical table name matches any +excluded_tables+ pattern (exact or glob).
    #
    # @param table_name [String, nil]
    # @return [Boolean]
    def excluded_table?(table_name)
      return false if table_name.nil? || table_name.to_s.empty?

      @excluded_tables.any? { |pat| ExclusionHelper.table_pattern_match?(pat.to_s, table_name.to_s) }
    end

    def output_dir_for(app)
      @output_dir || app.root.to_s
    end
  end
end
