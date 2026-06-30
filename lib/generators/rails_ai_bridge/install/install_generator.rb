# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'profile_resolver'
require_relative 'command_help'

module RailsAiBridge
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include CommandHelp

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

          # rails-ai-bridge configuration
          # All settings are commented out — uncomment only what you need to change.
          # Defaults are production-safe: read-only introspection, no HTTP exposure.
          # Run `rails ai:doctor` after changes to verify your setup.

          RailsAiBridge.configure do |config|
            # ---------------------------------------------------------------------------
            # Introspector preset
            # ---------------------------------------------------------------------------
            # Controls how much of your app is introspected when generating context files
            # and answering MCP tool requests.
            #
            # :standard (default) — #{standard_count} core introspectors covering the essentials:
            #   schema, models, routes, controllers, jobs, gems, conventions, tests, migrations
            #   Best for most apps. Fast and focused.
            #
            # :full — all #{full_count} introspectors (everything in :standard plus):
            #   views, Turbo/Stimulus, auth, API serializers, config, assets, DevOps
            #   Use for full-stack Hotwire apps or when AI needs frontend/auth/API context.
            #
            # :regulated — #{regulated_count} introspectors — omits schema, models, and migrations.
            #   Use for apps with strict data governance where schema must not be exposed.
            #
            # config.preset = :standard   # already the default — uncomment only to switch

            # Add individual introspectors on top of the preset (does not change the preset):
            # Effect: each listed symbol enables one additional introspector.
            # config.introspectors += %i[non_ar_models views turbo auth api database_stats]
            #
            # database_stats: adds small/medium/large/hot hints to table context using
            # PostgreSQL table statistics. Opt-in because it queries the DB at introspection time.

            # Disable a whole category at runtime (overrides preset and individual additions):
            # :domain_metadata disables schema + models + migrations + non_ar_models
            # config.disabled_introspection_categories << :domain_metadata

            # ---------------------------------------------------------------------------
            # Security exclusions
            # ---------------------------------------------------------------------------
            # These settings control what gets included in generated context files and
            # MCP tool responses. Excluded items are silently omitted — not replaced.

            # Tables to hide from schema introspection and model output.
            # Accepts exact table names or globs ("pii_*" matches pii_users, pii_logs, etc.)
            # Effect: excluded tables disappear from rails_get_schema and model details.
            # config.excluded_tables += %w[secrets audit_logs pii_*]

            # ActiveRecord models to exclude from introspection.
            # Effect: excluded models are not listed in any generated context file or MCP response.
            # config.excluded_models += %w[AdminUser InternalAuditLog]

            # Paths excluded from rails_search_code results.
            # Effect: files under these paths are skipped in code search results.
            # config.excluded_paths += %w[vendor/bundle node_modules]

            # ---------------------------------------------------------------------------
            # Domain model hints
            # ---------------------------------------------------------------------------
            # Mark your primary business models as core_entity. This affects:
            #   - Ordering in generated context files (core models listed first)
            #   - Semantic tier in rails_get_model_details responses ("core_entity")
            #   - .claude/rules/rails-models.md (tagged for Claude Code)
            # Effect: these models get promoted in AI context. Use your 3-7 most central models.
            # config.core_models += %w[User Order Project]

            # ---------------------------------------------------------------------------
            # Context output
            # ---------------------------------------------------------------------------
            # Controls how much detail goes into generated static files (CLAUDE.md, AGENTS.md, etc.)
            #
            # :compact (default) — ≤150 lines per file. Key models and routes are listed;
            #   everything else is referenced via MCP tools. Suitable for large apps.
            #   The AI asks MCP for details on demand — no context bloat.
            #
            # :full — dumps everything into the static files. No MCP needed for orientation,
            #   but files can be large. Best for small apps with fewer than ~30 models.
            #
            # config.context_mode = :compact   # already the default

            # Max lines for CLAUDE.md in compact mode (default: 150):
            # config.claude_max_lines = 150

            # Safety cap for MCP tool responses in characters (default: 120_000):
            # Oversized responses are truncated with a hint to use filters or pagination.
            # config.max_tool_response_chars = 120_000

            # Team-specific rules merged into Copilot and Codex output.
            # Effect: content of overrides.md is appended to .github/copilot-instructions.md
            # and AGENTS.md on each `rails ai:bridge` run.
            # IMPORTANT: Remove the first-line "<!-- rails-ai-bridge:omit-merge -->" guard
            # from config/rails_ai_bridge/overrides.md before this has any effect.
            # config.assistant_overrides_path = "config/rails_ai_bridge/overrides.md"

            # Model list size caps for compact output (0 = show no names, only MCP pointer):
            # Reduce these for apps with large model counts to keep files within size limits.
            # config.copilot_compact_model_list_limit = 15   # default
            # config.codex_compact_model_list_limit   = 15   # default

            # ==========================================================================
            # HTTP MCP / auto_mount — SECURITY CRITICAL
            # ==========================================================================
            # By default, MCP runs only via stdio (`rails ai:serve`), which is local-only
            # and safe. The HTTP transport is an opt-in alternative for clients that cannot
            # spawn sub-processes (e.g. browser-based AI tools, remote agents).
            #
            # Even though tools are read-only, the HTTP endpoint exposes routes, schema,
            # and code structure. Treat it as an internal service — keep it on localhost
            # unless you add authentication AND network controls.
            #
            # To enable HTTP MCP locally (development only):
            #   config.auto_mount = true
            #   config.http_path  = "/mcp"        # endpoint path
            #   config.http_bind  = "127.0.0.1"   # localhost only
            # Then start your Rails server and point your AI client to http://localhost:3000/mcp
            #
            # For production, you MUST also set allow_auto_mount_in_production = true AND
            # configure one of these auth mechanisms (highest priority first):
            #
            #   1. JWT decoder (bring your own JWT gem):
            #      config.mcp_jwt_decoder = ->(token) {
            #        JWT.decode(token, credentials.jwt_secret, true, algorithm: "HS256").first
            #      rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::ImmatureSignature
            #        nil
            #      }
            #
            #   2. Token resolver (Devise, database lookup, etc.):
            #      config.mcp_token_resolver = ->(token) { User.find_by(mcp_api_token: token) }
            #
            #   3. Static shared secret (simplest — fine for internal tools):
            #      config.http_mcp_token = "generate-a-long-random-secret"
            #      # ENV["RAILS_AI_BRIDGE_MCP_TOKEN"] takes precedence when set
            #
            # Require authentication on every HTTP MCP request. When true, requests
            # return 401 unless one of the auth mechanisms above is configured.
            # Default is false for backward compatibility with local development.
            # config.mcp.require_http_auth = true
            #
            # Timing-safe token comparison is built in, but add rate limiting too
            # (e.g. Rack::Attack throttle on config.http_path) to prevent brute-force.
            #
            # CORS for browser-based AI clients connecting over SSE.
            # Default is nil (no CORS headers). Set to ['*'] to allow any origin,
            # or to a list of exact origins such as ['https://app.example.com'].
            # config.mcp.cors_origins = ['https://app.example.com']
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

        begin
          profile = resolve_profile
        rescue ArgumentError
          say '  Run `rails generate rails_ai_bridge:install --profile=minimal` (or full/custom/mcp).', :yellow
          return
        end
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
        print_command_reference
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
          devin: 'Generate .devinrules?',
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
