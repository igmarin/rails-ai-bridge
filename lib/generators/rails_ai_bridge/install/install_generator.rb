# frozen_string_literal: true

require "json"

module RailsAiBridge
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install rails-ai-bridge: creates initializer, MCP config, and generates initial bridge files."

      ##
      # Creates a `.mcp.json` MCP server definition named "rails-ai-bridge".
      # The created file configures an MCP server that runs `bundle exec rails ai:serve` and is intended for auto-discovery by tools such as Claude Code and Cursor.
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

      ##
      # Create the Rails AI Bridge initializer at config/initializers/rails_ai_bridge.rb.
      #
      # The generated file is a commented configuration template that documents available
      # introspector presets (with counts interpolated from Configuration::PRESETS),
      # security exclusions, context/output controls, assistant override guidance, and
      # HTTP MCP auto-mount settings. Writes the initializer to disk and prints a
      ##
      # Creates config/initializers/rails_ai_bridge.rb containing a commented configuration guide for rails-ai-bridge.
      # The generated initializer documents introspector presets (with interpolated counts), options for enabling/disabling introspectors,
      # security exclusions (tables, models, paths), primary domain model hints, context/output controls, assistant override guidance,
      # and a SECURITY CRITICAL HTTP MCP / auto_mount section with recommended authentication approaches.
      # Writes the initializer file to config/initializers/rails_ai_bridge.rb and prints a green confirmation message.
      def create_initializer
        standard_count = RailsAiBridge::Configuration::PRESETS[:standard].size
        full_count     = RailsAiBridge::Configuration::PRESETS[:full].size
        regulated_count = RailsAiBridge::Configuration::PRESETS[:regulated].size

        create_file "config/initializers/rails_ai_bridge.rb", <<~RUBY
          # frozen_string_literal: true

          RailsAiBridge.configure do |config|
            # --- Introspector preset ---
            #   :standard  — #{standard_count} core introspectors (schema, models, routes, jobs, gems, conventions, controllers, tests, migrations)
            #   :full      — all #{full_count} introspectors (adds views, turbo, auth, API, config, assets, devops, etc.)
            #   :regulated — #{regulated_count} introspectors — no schema/models/migrations (for apps with strict data governance)
            # config.preset = :standard

            # Or cherry-pick individual introspectors:
            # config.introspectors += %i[views turbo auth api]

            # Disable whole product categories at runtime (schema + models + migrations, api, views/turbo/i18n):
            # config.disabled_introspection_categories << :domain_metadata

            # --- Security exclusions ---
            # Tables to hide from schema + model introspection (exact name or glob, e.g. "pii_*"):
            # config.excluded_tables += %w[secrets audit_logs pii_*]

            # Models to exclude from introspection:
            # config.excluded_models += %w[AdminUser InternalThing]

            # Primary domain models (semantic tier: core_entity in introspection & Claude rules):
            # config.core_models += %w[User Order Project]

            # Paths excluded from rails_search_code:
            # config.excluded_paths += %w[vendor/bundle]

            # --- Context output ---
            # :compact — ≤150 lines, references MCP tools for details (default)
            # :full    — full dump (good for small apps)
            # config.context_mode = :compact
            # config.claude_max_lines = 150
            # config.max_tool_response_chars = 120_000

            # Team rules merged into compact Copilot/Codex output (remove omit-merge line when ready):
            # config.assistant_overrides_path = "config/rails_ai_bridge/overrides.md"

            # Compact model list caps (0 = MCP pointer only, no names listed):
            # config.copilot_compact_model_list_limit = 5
            # config.codex_compact_model_list_limit = 3

            # ==========================================================================
            # HTTP MCP / auto_mount — SECURITY CRITICAL
            # ==========================================================================
            # Exposes read-only MCP tools over HTTP. Still reveals routes, schema, and
            # code layout — treat as sensitive. Prefer stdio (`rails ai:serve`) for local
            # AI clients.
            #
            # In production you MUST configure one auth mechanism AND set
            # allow_auto_mount_in_production = true. Options (highest priority first):
            #
            #   1. JWT decoder (no JWT gem required — supply your own lambda):
            #      config.mcp_jwt_decoder = ->(token) {
            #        JWT.decode(token, credentials.jwt_secret, true, algorithm: "HS256").first
            #      rescue JWT::DecodeError
            #        nil
            #      }
            #
            #   2. Token resolver (Devise, database lookup, etc.):
            #      config.mcp_token_resolver = ->(token) { User.find_by(mcp_api_token: token) }
            #
            #   3. Static shared secret:
            #      config.http_mcp_token = "generate-a-long-random-secret"
            #      # ENV["RAILS_AI_BRIDGE_MCP_TOKEN"] overrides this when set
            #
            # IMPORTANT: Token comparison is timing-safe but does NOT prevent
            # brute-force guessing. Add rate limiting on the MCP endpoint in
            # production (e.g. Rack::Attack throttle on config.http_path).
            #
            # config.auto_mount = false
            # config.allow_auto_mount_in_production = false
            # config.http_path = "/mcp"
            # config.http_port = 6029
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
          result = RailsAiBridge.generate_context(format: :all)
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
        say "  rails ai:bridge         # Generate all bridge files"
        say "  rails ai:bridge:claude   # Generate CLAUDE.md only"
        say "  rails ai:bridge:codex    # Generate AGENTS.md only"
        say "  rails ai:bridge:cursor   # Generate .cursorrules only"
        say "  rails ai:bridge:gemini   # Generate GEMINI.md only"
        say "  rails ai:serve           # Start MCP server (stdio)"
        say "  rails ai:inspect         # Print introspection summary"
        say ""
        say "Generated files per AI tool:", :yellow
        say "  Claude Code    → CLAUDE.md + .claude/rules/*.md"
        say "  OpenAI Codex   → AGENTS.md + .codex/README.md"
        say "  Cursor         → .cursorrules + .cursor/rules/*.mdc (incl. rails-engineering.mdc)"
        say "  Windsurf       → .windsurfrules + .windsurf/rules/*.md"
        say "  GitHub Copilot → .github/copilot-instructions.md + .github/instructions/*.instructions.md"
        say "  Gemini         → GEMINI.md"
        say ""
        say "MCP auto-discovery:", :yellow
        say "  .mcp.json is auto-detected by Claude Code and Cursor."
        say "  No manual MCP config needed — just open your project."
        say ""
        say "Bridge modes:", :yellow
        say "  rails ai:bridge         # compact mode (default, smart for any app size)"
        say "  rails ai:bridge:full    # full dump (good for small apps)"
        say ""
        say "Repo-specific Copilot/Codex rules:", :yellow
        say "  Edit config/rails_ai_bridge/overrides.md — remove the first-line omit-merge comment to enable merge."
        say "  See overrides.md.example for a suggested outline."
        say ""
        say "Commit bridge files and .mcp.json so your team benefits!", :green
      end
    end
  end
end
