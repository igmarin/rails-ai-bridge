# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'profile_resolver'

module RailsAiBridge
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Install rails-ai-bridge: creates initializer, MCP config, and generates initial bridge files.'

      class_option :skip_context, type: :boolean, default: false, desc: 'Skip interactive context file generation (useful for CI/CD)'
      class_option :profile, type: :string, desc: 'minimal|full|mcp|custom'

      ##
      # Creates a `.mcp.json` MCP server definition named "rails-ai-bridge".
      # The created file configures an MCP server that runs `bundle exec rails ai:serve` and is intended
      # for auto-discovery by tools such as Claude Code and Cursor.
      #
      # @return [void]
      def create_mcp_config
        mcp_config = {
          mcpServers: {
            'rails-ai-bridge' => {
              command: 'bundle',
              args: ['exec', 'rails', 'ai:serve']
            }
          }
        }
        create_file '.mcp.json', "#{JSON.pretty_generate(mcp_config)}\n"

        say 'Created .mcp.json (auto-discovered by Claude Code, Cursor, etc.)', :green
      end

      ##
      # Creates config/initializers/rails_ai_bridge.rb containing a commented configuration guide
      # for rails-ai-bridge. The generated initializer documents introspector presets (with interpolated
      # counts), options for enabling/disabling introspectors, security exclusions (tables, models,
      # paths), primary domain model hints, context/output controls, assistant override guidance, and
      # a SECURITY CRITICAL HTTP MCP / auto_mount section with recommended authentication approaches.
      #
      # @return [void]
      def create_initializer
        standard_count = RailsAiBridge::Configuration::PRESETS[:standard].size
        full_count     = RailsAiBridge::Configuration::PRESETS[:full].size
        regulated_count = RailsAiBridge::Configuration::PRESETS[:regulated].size

        create_file 'config/initializers/rails_ai_bridge.rb', <<~RUBY
          # frozen_string_literal: true

          RailsAiBridge.configure do |config|
            # --- Introspector preset ---
            #   :standard  — #{standard_count} core introspectors (schema, models, routes, jobs, gems, conventions, controllers, tests, migrations)
            #   :full      — all #{full_count} introspectors (adds views, turbo, auth, API, config, assets, devops, etc.)
            #   :regulated — #{regulated_count} introspectors — no schema/models/migrations (for apps with strict data governance)
            # config.preset = :standard

            # Or cherry-pick individual introspectors:
            # config.introspectors += %i[non_ar_models views turbo auth api]

            # Disable whole product categories at runtime (schema + models + migrations, optional :non_ar_models, api, views/turbo/i18n):
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
            #      rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::ImmatureSignature
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

        say 'Created config/initializers/rails_ai_bridge.rb', :green
      end

      ##
      # Creates the config/rails_ai_bridge/ directory with an overrides.md stub and an
      # overrides.md.example reference file. Skips each file if it already exists so the
      # method is safe to re-run (idempotent).
      #
      # @return [void]
      def create_assistant_overrides_template
        dir = 'config/rails_ai_bridge'
        empty_directory dir

        stub = File.join(destination_root, dir, 'overrides.md')
        unless File.exist?(stub)
          create_file "#{dir}/overrides.md", <<~MD
            <!-- rails-ai-bridge:omit-merge -->

          MD
          say "Created #{dir}/overrides.md (stub — remove omit-merge line when adding real rules)", :green
        end

        example = File.join(destination_root, dir, 'overrides.md.example')
        return if File.exist?(example)

        copy_file 'overrides.md.example', "#{dir}/overrides.md.example"
        say "Created #{dir}/overrides.md.example (reference outline, not merged)", :green
      end

      ##
      # Appends rails-ai-bridge-specific entries to .gitignore when the file exists and
      # the entries are not already present. Does nothing if .gitignore is absent.
      # Uses Thor's {#append_to_file} so the operation respects +--pretend+ (dry-run).
      #
      # @return [void]
      def add_to_gitignore
        gitignore_path = '.gitignore'
        gitignore_full = File.join(destination_root, gitignore_path)
        return unless File.exist?(gitignore_full)

        content = File.read(gitignore_full)
        append = []
        append << '.ai-context.json' unless content.include?('.ai-context.json')

        return unless append.any?

        append_to_file gitignore_path, "\n# rails-ai-bridge (JSON cache — markdown files should be committed)\n#{append.join("\n")}\n"
        say 'Updated .gitignore', :green
      end

      ##
      # Calls {RailsAiBridge.generate_context} to write initial bridge files (CLAUDE.md,
      # .cursorrules, etc.) according to the selected install profile. Skipped when
      # +Rails.application+ is not available. Any {StandardError} is rescued and reported
      # with the error class only — no raw message or sensitive path/credential details are
      # printed or logged. +Rails.logger.debug+ receives only the exception class name and a
      # short 12-character fingerprint derived from it, never the raw exception message.
      #
      # @return [void]
      def generate_context_files
        say ''
        say 'Generating AI bridge files...', :yellow

        return handle_skip_context if options[:skip_context]
        return handle_no_rails_app unless Rails.application

        profile = resolve_profile
        @selected_profile = profile

        case profile
        when 'mcp'
          say '  Skipped (MCP-only profile). Run `rails ai:bridge` to generate context files later.', :yellow
          return
        when 'minimal', 'full'
          formats = ProfileResolver.formats_for(profile)
          split_rules = ProfileResolver.split_rules_for(profile)
          return generate_context_for_formats(formats, split_rules: split_rules)
        end

        return say('  Skipped. Run `rails ai:bridge` to generate context files later.', :yellow) unless yes?('Generate AI assistant context files? (y/n)')

        formats = collect_selected_formats
        return say('  No formats selected. Run `rails ai:bridge` to generate context files later.', :yellow) if formats.empty?

        generate_context_for_formats(formats, split_rules: true)
      end

      ##
      # Prints post-install usage instructions to stdout: available rake tasks, generated
      # file locations per AI assistant, MCP auto-discovery notes, and bridge mode options.
      #
      # @return [void]
      def show_instructions
        return show_skip_context_instructions if options[:skip_context]

        show_full_instructions
      end

      private

      def show_skip_context_instructions
        say ''
        say 'rails-ai-bridge installed! Run `rails ai:bridge` to generate context files.', :green
      end

      def show_full_instructions
        say ''
        say '=' * 50, :cyan
        say ' rails-ai-bridge installed!', :cyan
        say '=' * 50, :cyan
        say ''
        say 'Commands:', :yellow
        say '  rails ai:bridge          # Generate all bridge files (compact mode)'
        say '  rails ai:bridge:full     # Full dump (good for small apps)'
        say '  rails ai:bridge:FORMAT   # Generate one format (claude, cursor, codex, gemini, copilot, windsurf)'
        say '  rails ai:watch           # Watch for changes and auto-regenerate'
        say '  rails ai:serve           # Start MCP server (stdio)'
        say '  rails ai:inspect         # Print introspection summary'
        say ''
        say 'Bridge files per tool:', :yellow
        say '  Claude Code    → CLAUDE.md + .claude/rules/*.md'
        say '  OpenAI Codex   → AGENTS.md + .codex/README.md'
        say '  Cursor         → .cursorrules + .cursor/rules/*.mdc'
        say '  Windsurf       → .windsurfrules + .windsurf/rules/*.md'
        say '  GitHub Copilot → .github/copilot-instructions.md + .github/instructions/*.md'
        say '  Gemini         → GEMINI.md'
        say ''
        say 'MCP: .mcp.json auto-detected by Claude Code and Cursor — no manual config needed.', :yellow
        say ''
        show_profile_summary
        say 'Custom rules: edit config/rails_ai_bridge/overrides.md (remove omit-merge line to enable)', :yellow
        say ''
        say 'Commit bridge files and .mcp.json so your team benefits!', :green
      end

      def show_profile_summary
        profile = selected_profile
        return unless profile && profile != 'custom' && ProfileResolver::PROFILE_OPTIONS.key?(profile)

        say "Profile: #{profile} — #{ProfileResolver.description_for(profile)}"
        say ''
      end

      def selected_profile
        @selected_profile || options[:profile]&.to_s&.downcase
      end

      def handle_skip_context
        say '  Skipped (--skip-context flag provided). Run `rails ai:bridge` to generate context files.', :yellow
      end

      def handle_no_rails_app
        say '  Skipped (Rails app not fully loaded). Run `rails ai:bridge` after install.', :yellow
      end

      def collect_selected_formats
        format_prompts = {
          claude: 'Generate CLAUDE.md?',
          cursor: 'Generate .cursorrules?',
          windsurf: 'Generate .windsurfrules?',
          copilot: 'Generate .github/copilot-instructions.md?',
          gemini: 'Generate GEMINI.md?',
          codex: 'Generate AGENTS.md?'
        }

        format_prompts.each_with_object([]) do |(format, prompt), formats|
          formats << format if yes?("#{prompt} (y/n)")
        end
      end

      def generate_context_for_formats(formats, split_rules: true)
        result = RailsAiBridge.generate_context(format: formats, split_rules: split_rules)
        report_context_generation_results(result)
      rescue StandardError => error
        handle_context_generation_error(error)
      end

      def report_context_generation_results(result)
        result[:written].each { |file| say "  Created #{file}", :green }
        result[:skipped].each { |file| say "  Unchanged #{file}", :blue }
      end

      def handle_context_generation_error(error)
        klass = error.class
        say "  Context generation failed (#{klass}). Run `rails ai:bridge` after install to retry.", :red
        error_id = Digest::SHA256.hexdigest(klass.name)[0, 12]
        Rails.logger.debug { "[rails-ai-bridge] generate_context error: #{klass} [#{error_id}]" }
      end

      def resolve_profile
        ProfileResolver.new(options[:profile], shell: self).call
      end
    end
  end
end
