# frozen_string_literal: true

require "json"

module RailsAiBridge
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :assistants, type: :string, default: nil,
                                desc: "Comma-separated formats: claude,codex,cursor,windsurf,copilot,json (non-interactive)"
      class_option :non_interactive, type: :boolean, default: false, desc: "Skip interactive prompts (default: all formats)"

      desc "Install rails-ai-bridge: creates initializer, MCP config, install.yml, and generates initial bridge files."

      def create_mcp_config
        create_file ".mcp.json", JSON.pretty_generate({
          mcpServers: {
            "rails-ai-bridge" => {
              command: "bundle",
              args: [ "exec", "rails", "ai:serve" ]
            }
          }
        }) + "\n"

        say "Created .mcp.json (auto-discovered by Claude Code, Cursor, etc.)", :green
      end

      def create_initializer
        standard_count = RailsAiBridge::Configuration::PRESETS[:standard].size
        full_count = RailsAiBridge::Configuration::PRESETS[:full].size
        regulated_count = RailsAiBridge::Configuration::PRESETS[:regulated].size

        create_file "config/initializers/rails_ai_bridge.rb", <<~RUBY
          # frozen_string_literal: true

          RailsAiBridge.configure do |config|
            # --- Introspector presets (optional; default is :standard / :compact) ---
            # :standard — #{standard_count} core introspectors (schema, models, routes, jobs, gems, conventions, controllers, tests, migrations)
            # :full     — all #{full_count} introspectors (views, turbo, auth, API, config, assets, devops, ...)
            # :large_monolith — same slices as :standard; pair with codex/copilot compact model limits = 0 for MCP-first workflows
            # :regulated — #{regulated_count} introspectors (no :schema, :models, :migrations) for less domain metadata on disk/MCP
            # config.preset = :standard

            # Or cherry-pick introspectors:
            # config.introspectors += %i[views turbo auth api]

            # Optional: remove introspector groups via product categories (see INTROSPECTION_CATEGORY_INTROSPECTORS in the gem).
            # config.disabled_introspection_categories << :domain_metadata

            # Models / tables to exclude from introspection (tables support globs, e.g. "pii_*")
            # config.excluded_models += %w[AdminUser InternalThing]
            # config.excluded_tables += %w[legacy_import_raw]

            # Paths excluded from rails_search_code
            # config.excluded_paths += %w[vendor/bundle]

            # Context mode: :compact (default) or :full
            # config.context_mode = :compact
            # config.claude_max_lines = 150
            # config.max_tool_response_chars = 120_000

            # Team rules merged into compact Copilot/Codex (remove omit-merge line when ready)
            # config.assistant_overrides_path = "config/rails_ai_bridge/overrides.md"

            # Compact model lists (0 = MCP pointer only)
            # config.copilot_compact_model_list_limit = 5
            # config.codex_compact_model_list_limit = 3

            # =============================================================================
            # HTTP MCP / auto_mount — SECURITY CRITICAL
            # =============================================================================
            # auto_mount exposes read-only MCP tools over HTTP. They still reveal routes, schema,
            # controllers, and code layout — treat as sensitive. Prefer stdio (`rails ai:serve`) for local AI clients.
            #
            # REQUIREMENTS:
            # - Bind to 127.0.0.1 in development unless you add network + auth controls.
            # - Production: set http_mcp_token (or ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]), allow_auto_mount_in_production = true,
            #   and review SECURITY.md before enabling.
            #
            # Skimming this block is dangerous; read docs/GUIDE.md and SECURITY.md before turning auto_mount on.
            # =============================================================================
            # config.auto_mount = false
            # config.allow_auto_mount_in_production = false
            # config.http_mcp_token = "generate-a-long-random-secret"
            # ENV["RAILS_AI_BRIDGE_MCP_TOKEN"] overrides http_mcp_token when set
            # config.http_path  = "/mcp"
            # config.http_bind   = "127.0.0.1"
            # config.http_port   = 6029
          end
        RUBY

        say "Created config/initializers/rails_ai_bridge.rb", :green
      end

      def create_assistant_overrides_template
        dir = "config/rails_ai_bridge"
        FileUtils.mkdir_p(File.join(destination_root, dir))

        stub = File.join(destination_root, dir, "overrides.md")
        unless File.exist?(stub)
          create_file "#{dir}/overrides.md", <<~MD
            <!-- rails-ai-bridge:omit-merge -->

          MD
          say "Created #{dir}/overrides.md (stub — remove omit-merge line when adding real rules)", :green
        end

        example = File.join(destination_root, dir, "overrides.md.example")
        unless File.exist?(example)
          copy_file "overrides.md.example", "#{dir}/overrides.md.example"
          say "Created #{dir}/overrides.md.example (reference outline, not merged)", :green
        end
      end

      def create_install_preferences
        require "rails_ai_bridge"

        formats = resolve_assistant_format_selection
        AssistantFormatsPreference.write!(formats: formats)
        say "Created #{AssistantFormatsPreference::RELATIVE_PATH} — `rails ai:bridge` targets: #{formats.join(", ")}", :green
      end

      def add_to_gitignore
        gitignore = Rails.root.join(".gitignore")
        return unless File.exist?(gitignore)

        content = File.read(gitignore)
        append = []
        append << ".ai-context.json" unless content.include?(".ai-context.json")

        if append.any?
          File.open(gitignore, "a") do |f|
            f.puts ""
            f.puts "# rails-ai-bridge (JSON cache — markdown files should be committed)"
            append.each { |line| f.puts line }
          end
          say "Updated .gitignore", :green
        end
      end

      def generate_context_files
        say ""
        say "Generating AI bridge files...", :yellow

        if Rails.application
          require "rails_ai_bridge"
          result = RailsAiBridge.generate_context(format: :install)
          result[:written].each { |file| say "  Created #{file}", :green }
          result[:skipped].each { |file| say "  Unchanged #{file}", :blue }
        else
          say "  Skipped (Rails app not fully loaded). Run `rails ai:bridge` after install.", :yellow
        end
      end

      def show_instructions
        say ""
        say "=" * 50, :cyan
        say " rails-ai-bridge installed!", :cyan
        say "=" * 50, :cyan
        say ""
        say "Quick start:", :yellow
        say "  rails ai:bridge              # Generate files from config/rails_ai_bridge/install.yml"
        say "  rails ai:bridge:all          # Every format (including JSON), ignores install.yml"
        say "  rails ai:bridge:claude       # CLAUDE.md only"
        say "  rails ai:bridge:codex        # AGENTS.md only"
        say "  rails ai:bridge:json         # .ai-context.json only (machine-readable bundle)"
        say "  rails ai:serve               # MCP server (stdio)"
        say "  rails ai:inspect             # Introspection summary"
        say ""
        say "Generated files per AI tool:", :yellow
        say "  Claude Code    → CLAUDE.md + .claude/rules/*.md"
        say "  OpenAI Codex   → AGENTS.md + .codex/README.md"
        say "  Cursor         → .cursorrules + .cursor/rules/*.mdc (incl. rails-engineering.mdc)"
        say "  Windsurf       → .windsurfrules + .windsurf/rules/*.md"
        say "  GitHub Copilot → .github/copilot-instructions.md + .github/instructions/*.instructions.md"
        say ""
        say "Copilot merges:", :yellow
        say "  Managed content is wrapped in HTML comments in copilot-instructions.md."
        say "  Existing files without markers are skipped unless RAILS_AI_BRIDGE_COPILOT_MERGE=overwrite."
        say ""
        say "MCP auto-discovery:", :yellow
        say "  .mcp.json is auto-detected by Claude Code and Cursor."
        say ""
        say "Bridge modes:", :yellow
        say "  rails ai:bridge:full    # full dump into context files (good for small apps)"
        say ""
        say "Repo-specific rules:", :yellow
        say "  Edit config/rails_ai_bridge/overrides.md — remove the first-line omit-merge comment to enable merge."
        say "  See overrides.md.example for a suggested outline."
        say ""
        say "Commit bridge files and .mcp.json so your team benefits!", :green
      end

      private

      def resolve_assistant_format_selection
        if options[:assistants].present?
          list = parse_assistant_list(options[:assistants])
          return AssistantFormatsPreference::FORMAT_KEYS if list.empty?

          return list
        end

        return AssistantFormatsPreference::FORMAT_KEYS if options[:non_interactive] || !$stdin.tty?

        say ""
        say "Which assistant outputs should `rails ai:bridge` generate?", :yellow
        say "  claude, codex, cursor, windsurf, copilot, json — or 'all' (default)."
        ans = ask("formats [all]:", default: "all")
        return AssistantFormatsPreference::FORMAT_KEYS if ans.strip.empty? || ans.strip.casecmp("all").zero?

        list = parse_assistant_list(ans)
        list.empty? ? AssistantFormatsPreference::FORMAT_KEYS : list
      end

      def parse_assistant_list(str)
        str.to_s.split(",").map(&:strip).map(&:downcase).map(&:to_sym) & AssistantFormatsPreference::FORMAT_KEYS
      end
    end
  end
end
