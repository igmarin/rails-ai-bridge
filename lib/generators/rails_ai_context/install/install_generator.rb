# frozen_string_literal: true

require "json"

module RailsAiContext
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install rails-ai-context: creates initializer, MCP config, and generates initial context files."

      def create_mcp_config
        create_file ".mcp.json", JSON.pretty_generate({
          mcpServers: {
            "rails-ai-context" => {
              command: "bundle",
              args: [ "exec", "rails", "ai:serve" ]
            }
          }
        }) + "\n"

        say "Created .mcp.json (auto-discovered by Claude Code, Cursor, etc.)", :green
      end

      def create_initializer
        create_file "config/initializers/rails_ai_context.rb", <<~RUBY
          # frozen_string_literal: true

          RailsAiContext.configure do |config|
            # Introspector preset:
            #   :standard — 8 core introspectors (schema, models, routes, jobs, gems, conventions, controllers, tests)
            #   :full     — all 21 introspectors (adds views, turbo, auth, API, config, assets, devops, etc.)
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

            # Auto-mount HTTP MCP endpoint at /mcp
            # config.auto_mount = false
            # config.http_path  = "/mcp"
            # config.http_port  = 6029
          end
        RUBY

        say "Created config/initializers/rails_ai_context.rb", :green
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
            f.puts "# rails-ai-context (JSON cache — markdown files should be committed)"
            append.each { |line| f.puts line }
          end
          say "Updated .gitignore", :green
        end
      end

      def generate_context_files
        say ""
        say "Generating AI context files...", :yellow

        if Rails.application
          require "rails_ai_context"
          context = RailsAiContext.introspect
          files = RailsAiContext.generate_context(format: :all)
          files.each { |f| say "  Created #{f}", :green }
        else
          say "  Skipped (Rails app not fully loaded). Run `rails ai:context` after install.", :yellow
        end
      end

      def show_instructions
        say ""
        say "=" * 50, :cyan
        say " rails-ai-context installed!", :cyan
        say "=" * 50, :cyan
        say ""
        say "Quick start:", :yellow
        say "  rails ai:context         # Generate all context files"
        say "  rails ai:context:claude   # Generate CLAUDE.md only"
        say "  rails ai:context:cursor   # Generate .cursorrules only"
        say "  rails ai:serve           # Start MCP server (stdio)"
        say "  rails ai:inspect         # Print introspection summary"
        say ""
        say "Generated files per AI tool:", :yellow
        say "  Claude Code    → CLAUDE.md + .claude/rules/*.md"
        say "  Cursor         → .cursorrules + .cursor/rules/*.mdc"
        say "  Windsurf       → .windsurfrules + .windsurf/rules/*.md"
        say "  GitHub Copilot → .github/copilot-instructions.md + .github/instructions/*.instructions.md"
        say ""
        say "MCP auto-discovery:", :yellow
        say "  .mcp.json is auto-detected by Claude Code and Cursor."
        say "  No manual MCP config needed — just open your project."
        say ""
        say "Context modes:", :yellow
        say "  rails ai:context         # compact mode (default, smart for any app size)"
        say "  rails ai:context:full    # full dump (good for small apps)"
        say ""
        say "Commit context files and .mcp.json so your team benefits!", :green
      end
    end
  end
end
