# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Base class for AI assistant provider serializers (Claude, Copilot, Gemini, Codex, Cursor, Windsurf).
      # Shared compact-mode sections: header, stack, models, gems, architecture, MCP guide, commands, footer.
      class BaseProviderSerializer
        MAX_KEY_MODELS   = 15
        MAX_PATTERNS     = 8
        MAX_CONFIG_FILES = 5

        attr_reader :context, :config

        # @param context [Hash] Introspection hash from {Introspector#call}.
        # @param config [RailsAiBridge::Configuration] Bridge configuration.
        def initialize(context, config: RailsAiBridge.configuration)
          @context = context
          @config = config
        end

        # Renders the default compact AI context document (newline-joined sections).
        # Enforces {RailsAiBridge::Configuration#claude_max_lines} by trimming with an MCP pointer when exceeded.
        # Subclasses may override entirely or compose with individual `#render_*` helpers.
        #
        # @return [String] Compact markdown body.
        def render_compact
          lines = []
          lines.concat(render_header)
          lines.concat(render_stack_overview)
          lines.concat(render_key_models)
          lines.concat(render_notable_gems)
          lines.concat(render_architecture)
          lines.concat(render_key_considerations)
          lines.concat(Formatters::Providers::McpGuideFormatter.new(context).call.split("\n"))
          lines.concat(render_key_config_files)
          lines.concat(render_commands)
          lines.concat(render_footer)

          enforce_max_lines(lines).join("\n")
        end

        private

        # Enforces claude_max_lines by trimming and adding MCP pointer.
        # @param lines [Array<String>] Full document lines.
        # @return [Array<String>] Trimmed lines or original if within limit.
        def enforce_max_lines(lines)
          max = @config.claude_max_lines
          return lines if lines.size <= max

          trimmed = lines.first(max - 2)
          trimmed << ''
          trimmed << '_Context trimmed. Use MCP tools for full details._'
          trimmed
        end

        # Formats a single model line with complexity metadata.
        # @param name [String] Model name.
        # @param data [Hash] Model introspection data.
        # @param schema_tables [Hash] Schema tables hash.
        # @param migrations [Hash, nil] Migrations hash.
        # @return [String] Formatted model line.
        def format_model_line(name, data, schema_tables, migrations)
          associations = data[:associations] || []
          assoc_count = associations.size
          val_count   = (data[:validations] || []).size
          enum_names  = (data[:enums] || {}).keys
          top_assocs  = associations.first(3).map { |association| "#{association[:type]} :#{association[:name]}" }.join(', ')
          table_name  = data[:table_name]

          line = "- **#{name}**"
          line += " (#{assoc_count}a, #{val_count}v)" if assoc_count.positive? || val_count.positive?
          line += " [enums: #{enum_names.join(', ')}]" if enum_names.any?

          cols = ContextSummary.top_columns(schema_tables[table_name])
          line += " [cols: #{cols.map { |column| "#{column[:name]}:#{column[:type]}" }.join(', ')}]" if cols.any?

          line += ' [recently migrated]' if table_name && recently_migrated?(table_name, migrations)
          line += " — #{top_assocs}" if top_assocs.present?
          line
        end

        # Extracts notable gems from various possible keys.
        # @param gems [Hash, nil] Gems hash from context.
        # @return [Array<Hash>] List of notable gem hashes.
        def extract_notable_gems(gems)
          return [] unless gems.is_a?(Hash) && !gems[:error]

          gems[:notable_gems] || gems[:notable] || gems[:detected] || []
        end

        # Checks if a table was recently migrated.
        # Handles both recent_tables array and recent migrations list formats.
        # @param table_name [String] Name of the table to check.
        # @param migrations [Hash, nil] Migrations hash from context.
        # @return [Boolean] true if the table was recently migrated.
        def recently_migrated?(table_name, migrations)
          return false unless table_name && migrations.is_a?(Hash)

          # Check for recent_tables array format
          return true if migrations[:recent_tables]&.include?(table_name)

          # Check for recent migrations list format
          recent = migrations[:recent] || migrations[:recent_migrations] || []
          recent.any? { |mig| mig[:filename]&.include?(table_name) }
        end

        # Returns database line or nil if unavailable.
        # @param schema [Hash, nil] Schema hash from context.
        # @return [String, nil]
        def database_stack_line(schema = context[:schema])
          "- Database: #{schema[:adapter]} — #{schema[:total_tables]} tables" if schema.is_a?(Hash) && !schema[:error]
        end

        # Returns models count line or nil if unavailable.
        # @param models [Hash, nil] Models hash from context.
        # @return [String, nil]
        def models_stack_line(models = context[:models])
          "- Models: #{models.size}" if models.is_a?(Hash) && !models[:error]
        end

        # Returns auth line with detected providers or nil.
        # @param auth [Hash, nil] Auth hash from context.
        # @return [String, nil]
        def auth_stack_line(auth = context[:auth])
          return nil unless auth.is_a?(Hash) && !auth[:error]

          parts = []
          parts << 'Devise' if auth.dig(:authentication, :devise)&.any?
          parts << 'Rails 8 auth' if auth.dig(:authentication, :rails_auth)
          parts << 'Pundit' if auth.dig(:authorization, :pundit)&.any?
          parts << 'CanCanCan' if auth.dig(:authorization, :cancancan)
          "- Auth: #{parts.join(' + ')}" if parts.any?
        end

        # Returns async jobs/mailers/channels line or nil.
        # @param jobs [Hash, nil] Jobs hash from context.
        # @return [String, nil]
        def async_stack_line(jobs = context[:jobs])
          return nil unless jobs.is_a?(Hash) && !jobs[:error]

          job_count = jobs[:jobs]&.size || 0
          mailer_count = jobs[:mailers]&.size || 0
          channel_count = jobs[:channels]&.size || 0
          parts = []
          parts << "#{job_count} jobs" if job_count.positive?
          parts << "#{mailer_count} mailers" if mailer_count.positive?
          parts << "#{channel_count} channels" if channel_count.positive?
          "- Async: #{parts.join(', ')}" if parts.any?
        end

        # Returns migrations line with pending count or nil.
        # @param migrations [Hash, nil] Migrations hash from context.
        # @return [String, nil]
        def migrations_stack_line(migrations = context[:migrations])
          return nil unless migrations.is_a?(Hash) && !migrations[:error]

          pending = migrations[:pending]
          "- Migrations: #{migrations[:total]} total, #{pending&.size || 0} pending"
        end

        public

        # Renders the header section of the context file.
        # @return [Array<String>] Lines for the header.
        def render_header
          [
            "# #{context[:app_name]} — AI Context",
            '',
            "> Auto-generated by rails-ai-bridge v#{RailsAiBridge::VERSION}",
            "> Generated: #{context[:generated_at]}",
            "> Rails #{context[:rails_version]} | Ruby #{context[:ruby_version]}",
            '',
            "This file provides a high-level overview of this Rails application's",
            'structure, patterns, and conventions. As an AI assistant, use this context',
            'to quickly understand the project and generate idiomatic code that',
            'adheres to its design decisions. For deeper dives, use the live',
            'MCP tools referenced throughout this document.'
          ]
        end

        # Renders the stack overview section.
        # Includes database adapter/table count, model count, routes, auth gems,
        # async jobs/mailers/channels, and pending migrations when available.
        # Silently skips any sub-section whose context key is missing or has an +:error+ key.
        #
        # @return [Array<String>] Lines for the stack overview section, always non-empty.
        def render_stack_overview
          lines = ['## Stack']
          lines << database_stack_line
          lines << models_stack_line
          lines << ContextSummary.routes_stack_line(context)
          lines << auth_stack_line
          lines << async_stack_line
          lines << migrations_stack_line
          lines.compact << ''
        end

        # Renders the key models section, sorted by complexity score (associations, validations, callbacks, scopes).
        # Caps display at {MAX_KEY_MODELS} models and appends an overflow hint when more exist.
        # Returns +[]+ when +context[:models]+ is nil, non-Hash, or has an +:error+ key.
        #
        # @return [Array<String>] Lines for the key models section, or +[]+ if unavailable.
        def render_key_models
          models = context[:models]
          return [] unless models.is_a?(Hash) && !models[:error] && models.any?

          schema_tables = context.dig(:schema, :tables) || {}
          migrations    = context[:migrations]
          max_show = MAX_KEY_MODELS

          lines = ['## Key Models',
                   'The following are the most architecturally significant models, ordered by complexity:']
          sorted_names = models.sort_by { |_name, data| -ContextSummary.model_complexity_score(data) }.map(&:first)
          sorted_names.first(max_show).each do |name|
            data = models[name]
            lines << format_model_line(name, data, schema_tables, migrations)
          end
          lines << "- _...#{models.size - max_show} more (use `rails_get_model_details` tool)_" if models.size > max_show
          lines << ''
          lines
        end

        # Renders the notable gems section grouped by category.
        # Looks for notable gems under +:notable_gems+, +:notable+, or +:detected+ keys.
        # Returns +[]+ when gems are absent, have an +:error+ key, or the list is empty.
        #
        # @return [Array<String>] Lines for the notable gems section, or +[]+ if unavailable.
        def render_notable_gems
          notable = extract_notable_gems(context[:gems])
          return [] if notable.empty?

          lines = ['## Gems', 'Key gems, categorized by their primary function:']
          grouped = notable.group_by { |g| g[:category]&.to_s || 'other' }
          grouped.each do |category, gem_list|
            names = gem_list.map { |g| g[:name] }.join(', ')
            lines << "- **#{category}**: #{names}"
          end
          lines << ''
          lines
        end

        # Renders the architecture section with detected styles and common patterns.
        # Caps patterns at {MAX_PATTERNS} entries. Returns +[]+ when conventions are absent,
        # have an +:error+ key, or both +:architecture+ and +:patterns+ are empty.
        #
        # @return [Array<String>] Lines for the architecture section, or +[]+ if unavailable.
        def render_architecture
          conv = context[:conventions]
          return [] unless conv.is_a?(Hash) && !conv[:error]

          arch = conv[:architecture] || []
          patterns = conv[:patterns] || []
          return [] if arch.empty? && patterns.empty?

          lines = ['## Architecture', 'Detected architectural styles and common patterns:']
          arch.each { |p| lines << "- #{p}" }
          patterns.first(MAX_PATTERNS).each { |p| lines << "- #{p}" }
          lines << ''
          lines
        end

        # Renders the static key considerations section covering performance, security,
        # data drift, and MCP exposure. Content is fixed and does not depend on context.
        #
        # @return [Array<String>] Lines for the key considerations section.
        def render_key_considerations
          [
            '## Key Considerations',
            '- **Performance:** For large or frequently accessed tables, always consider database performance. ' \
            'Use the `rails_get_schema` tool to verify indexes and be mindful of N+1 queries by using `includes` and other ActiveRecord optimizations.',
            '- **Security:** Treat all user-provided input as untrusted. Always use strong parameters in controllers ' \
            'and be aware of potential security vulnerabilities when using gems like `ransack` or `pg_search`.',
            '- **Data Drift:** This document is a snapshot. For the most up-to-date information, especially regarding schema and routes, use the live MCP tools.',
            '- **MCP Exposure:** The MCP tools are read-only but expose sensitive application structure. Avoid exposing the HTTP transport on untrusted networks.',
            ''
          ]
        end

        # Renders the key configuration files section.
        # Caps display at {MAX_CONFIG_FILES} files. Returns +[]+ when conventions are absent,
        # have an +:error+ key, or +:config_files+ is empty.
        #
        # @return [Array<String>] Lines for the key config files section, or +[]+ if unavailable.
        def render_key_config_files
          conv = context[:conventions]
          return [] unless conv.is_a?(Hash) && !conv[:error]

          config_files = conv[:config_files] || []
          return [] if config_files.empty?

          lines = ['## Key Config Files', 'Core configuration files for this application:']
          config_files.first(MAX_CONFIG_FILES).each { |f| lines << "- `#{f}`" }
          lines << ''
          lines
        end

        # Renders the command reference section with common dev, test, lint and migration commands.
        # The test command is resolved via {ContextSummary.test_command}.
        #
        # @return [Array<String>] Lines for the commands section.
        def render_commands
          [
            '## Commands',
            '- `bin/dev` — start dev server',
            "- `#{ContextSummary.test_command(context)}` — run tests",
            '- `bundle exec rubocop` — run linter',
            '- `rails db:migrate` — run pending migrations',
            ''
          ]
        end

        # Renders the closing engineering rules and regeneration attribution footer.
        # Delegates to {SharedAssistantGuidance.compact_engineering_rules_footer_lines}.
        #
        # @return [Array<String>] Lines for the footer section.
        def render_footer
          SharedAssistantGuidance.compact_engineering_rules_footer_lines(context)
        end
      end
    end
  end
end
