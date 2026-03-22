# frozen_string_literal: true

require "json"

module RailsAiBridge
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install rails-ai-bridge: creates initializer, MCP config, and generates initial bridge files."

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

        create_file "config/initializers/rails_ai_bridge.rb", <<~RUBY
          # frozen_string_literal: true

          RailsAiBridge.configure do |config|
            # Introspector preset:
            #   :standard — #{standard_count} core introspectors (schema, models, routes, jobs, gems, conventions, controllers, tests, migrations)
            #   :full     — all #{full_count} introspectors (adds views, turbo, auth, API, config, assets, devops, etc.)
            # config.preset = :standard

            # Or cherry-pick individual introspectors:
            # config.introspectors += %i[views turbo auth api]

            # Models to exclude from introspection
            # config.excluded_models += %w[AdminUser InternalThing]

            # Paths to exclude from code search
            # config.excluded_paths += %w[vendor/bundle]

            # Context mode for generated files (CLAUDE.md, .cursorrules, etc.)
            # :compact — smart, ≤150 lines, references MCP tools for details (default)
            # :full    — dumps everything into context files (good for small apps <30 models)
            # config.context_mode = :compact

            # Max lines for CLAUDE.md in compact mode
            # config.claude_max_lines = 150

            # Max response size for MCP tool results (chars). Safety net for large apps.
            # config.max_tool_response_chars = 120_000

            # Optional: path to markdown merged into compact Copilot + Codex (default: config/rails_ai_bridge/overrides.md).
            # The install stub uses <!-- rails-ai-bridge:omit-merge --> on line 1 — delete it when adding real rules
            # (until then nothing is merged). See config/rails_ai_bridge/overrides.md.example for an outline.
            # config.assistant_overrides_path = "config/rails_ai_bridge/overrides.md"

            # Compact file model name caps (0 = MCP pointer only, no names listed)
            # config.copilot_compact_model_list_limit = 5
            # config.codex_compact_model_list_limit = 3

            # Auto-mount HTTP MCP endpoint at /mcp (see SECURITY.md — production needs token + explicit opt-in)
            # config.auto_mount = false
            # config.allow_auto_mount_in_production = false
            # config.http_mcp_token = "generate-a-long-random-secret"
            # ENV["RAILS_AI_BRIDGE_MCP_TOKEN"] overrides http_mcp_token when set
            # config.http_path  = "/mcp"
            # config.http_port  = 6029
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
        say "  rails ai:serve           # Start MCP server (stdio)"
        say "  rails ai:inspect         # Print introspection summary"
        say ""
        say "Generated files per AI tool:", :yellow
        say "  Claude Code    → CLAUDE.md + .claude/rules/*.md"
        say "  OpenAI Codex   → AGENTS.md + .codex/README.md"
        say "  Cursor         → .cursorrules + .cursor/rules/*.mdc (incl. rails-engineering.mdc)"
        say "  Windsurf       → .windsurfrules + .windsurf/rules/*.md"
        say "  GitHub Copilot → .github/copilot-instructions.md + .github/instructions/*.instructions.md"
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
