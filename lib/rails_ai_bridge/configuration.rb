# frozen_string_literal: true

module RailsAiBridge
  # Holds user-facing options for introspection presets, exclusions, MCP HTTP, and context generation.
  #
  # Presets ({PRESETS}) set the base +introspectors+ list; {#disabled_introspection_categories} and
  # {#preset=} refine what runs. {#effective_introspectors} is what the introspector and MCP layer use.
  #
  # @see Introspector
  # @see RailsAiBridge.configuration
  class Configuration
    # Named introspector lists for {#preset=}.
    #
    # @return [Hash<Symbol, Array<Symbol>>]
    PRESETS = {
      standard: %i[schema models routes jobs gems conventions controllers tests migrations],
      full: %i[schema models routes jobs gems conventions stimulus controllers views turbo
               i18n config active_storage action_text auth api tests rake_tasks assets
               devops action_mailbox migrations seeds middleware engines multi_database],
      # Same introspector set as :standard; use for large apps that want MCP-first model/schema detail (tune list limits in the initializer).
      large_monolith: %i[schema models routes jobs gems conventions controllers tests migrations],
      # Minimal disk/MCP surface: no schema, models, or migrations introspection (add them back if you need domain tools).
      regulated: %i[routes jobs gems conventions controllers tests]
    }.freeze

    # Product-level categories that subtract introspectors from the active preset (see +#effective_introspectors+).
    #
    # @return [Hash<Symbol, Array<Symbol>>]
    INTROSPECTION_CATEGORY_INTROSPECTORS = {
      domain_metadata: %i[schema models migrations],
      persistence_surface: %i[schema models],
      api_surface: %i[api],
      ui_stack: %i[views stimulus turbo i18n]
    }.freeze

    # Order for {#inferred_preset_name}: more specific presets before subsets (e.g. :large_monolith vs :standard).
    #
    # @return [Array<Symbol>]
    PRESET_INFERENCE_ORDER = %i[regulated large_monolith full standard].freeze

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

    # Nested MCP HTTP auth / policy settings ({RailsAiBridge::Mcp::Settings}).
    #
    # @return [RailsAiBridge::Mcp::Settings]
    def mcp
      @mcp ||= Mcp::Settings.new
    end

    # Initializes defaults (standard preset, compact mode, common +excluded_models+, empty exclusions).
    #
    # @return [void]
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
    end

    # Replaces +introspectors+ with the list for the given preset name.
    #
    # @param name [Symbol, String] one of {PRESETS} keys
    # @raise [ArgumentError] when the preset is unknown
    # @return [void]
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

    # Best-effort preset label when +introspectors+ exactly match a known preset; otherwise +:custom+.
    #
    # @return [Symbol] a key from {PRESETS} if the sorted list matches, else +:custom+
    def inferred_preset_name
      sorted = introspectors.sort
      self.class::PRESET_INFERENCE_ORDER.each do |key|
        list = self.class::PRESETS[key]
        return key if list && sorted == list.sort
      end
      :custom
    end

    # Root-relative or absolute output directory for generated files.
    #
    # @param app [Rails::Application]
    # @return [String] filesystem path
    def output_dir_for(app)
      @output_dir || app.root.to_s
    end
  end
end
