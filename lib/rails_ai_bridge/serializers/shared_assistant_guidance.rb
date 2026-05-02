# frozen_string_literal: true

require 'pathname'

module RailsAiBridge
  module Serializers
    # Shared high-signal copy for Copilot, Codex, Cursor, and legacy .cursorrules compact output.
    #
    # @see ContextSummary
    module SharedAssistantGuidance
      module_function

      # First line of +overrides.md+ while in stub mode — file is not merged until removed.
      OMIT_MERGE_FIRST_LINE = /\A<!--\s*rails-ai-bridge:omit-merge\s*-->\z/i

      # @return [Array<String>] markdown lines including heading and trailing blank line
      def compact_engineering_rules_lines
        [
          '## Engineering rules (read first)',
          '',
          'Defaults for this codebase unless existing files clearly show a different pattern.',
          '',
          '### Controllers & strong parameters',
          '- Permit attributes explicitly; never pass raw `params` into `Model.new`, `update`, or `assign_attributes`.',
          '- Extend `permit` lists deliberately when adding fields; mirror neighboring actions in the same controller.',
          '',
          '### Authentication & authorization',
          "- Guard mutating and sensitive reads with the app's existing auth (e.g. `before_action` filters, policies). A public route does not imply public data.",
          '- Use `rails_get_controllers` for filters and `rails_get_conventions` for architecture hints when unsure.',
          '',
          '### Data access & performance',
          '- Avoid N+1: use `includes` / `preload` / `eager_load` for associations used in views or serializers.',
          '- Do not load unbounded collections: paginate list endpoints, use `find_each` in jobs, stream large exports.',
          '- Large or hot tables: check indexes before new `WHERE`/`ORDER BY`; use `rails_get_schema` before heavy queries.',
          '',
          '### Security & inputs',
          '- Treat external input as untrusted; avoid `constantize` / `send` / `eval` on user-controlled strings and raw SQL string interpolation.',
          '- Allow-list host or path for any redirect built from user input (open-redirect risk).',
          '',
          '### Testing',
          '- Prefer request or system specs for HTTP flows and integration; keep model specs tight for business rules.',
          "- Run the project's test suite after substantive edits (often `bundle exec rspec` — confirm framework via `rails_get_test_info`).",
          '',
          '### Repo-specific constraints',
          '- Hot tables, tenant/auth scoping, mandatory spec types, and internal policies belong in `config/rails_ai_bridge/overrides.md`.',
          '- Remove or replace the first-line `<!-- rails-ai-bridge:omit-merge -->` marker before that file is merged into Copilot/Codex; ' \
          'use `overrides.md.example` as a starting outline.',
          '',
          '_Regenerated files are snapshots. Re-merge team-specific performance, security, or compliance rules at the top after `rails ai:bridge`, ' \
          'or keep them in separate committed instruction files._',
          ''
        ]
      end

      # Concrete Rails patterns to complement generic performance bullets (gem cannot know your largest tables).
      #
      # @return [Array<String>] markdown lines including heading; no trailing blank line required (caller adds spacing)
      def rails_performance_examples_lines
        [
          '### Rails patterns (large data & hot paths)',
          '- Never use `Model.all` (or unscoped relations) in request cycles — use `where`, `limit`, or pagination.',
          '- Background jobs: iterate with `find_each` or `in_batches` instead of `each` on large relations.',
          '- Prefer `exists?` / `count` with care on huge tables; narrow with `where` first; avoid `length` on loaded associations for big sets.',
          '- Wide rows: fetch only needed columns with `select` / `pluck` when you do not need full records.',
          '- Enable or use `strict_loading` in development/test to catch accidental N+1s early.',
          '- Before adding filters or `ORDER BY` on high-volume tables, confirm indexes via `rails_get_schema` and migrations.',
          ''
        ]
      end

      # Condensed rules for always-on Cursor MDC (stay under ~35 lines of body).
      #
      # @param show_overrides_pointer [Boolean] append pointer to +config/rails_ai_bridge/overrides.md+
      # @return [Array<String>] markdown body lines (no YAML frontmatter)
      def cursor_engineering_mdc_body_lines(show_overrides_pointer: false)
        lines = [
          '# Engineering essentials',
          '',
          '- **Strong params**: permit explicitly; never mass-assign raw `params`.',
          '- **Auth**: protect mutations and sensitive reads; public route ≠ public data.',
          '- **N+1**: `includes` / `preload` / `eager_load` for associations in views and serializers.',
          '- **Bounds**: paginate HTTP lists; `find_each` / `in_batches` in jobs; no `Model.all` in requests.',
          '- **Large tables**: narrow queries; check indexes before new filters/sorts; use `rails_get_schema`.',
          '- **Security**: no `constantize`/`send`/`eval` on user input; no SQL string interpolation; allow-list redirects.',
          '- **Tests**: request/system specs for HTTP; confirm runner with `rails_get_test_info`.',
          '',
          'Generated files are **snapshots** — prefer `rails_*` MCP tools for current structure.',
          'Full engineering rules: `.github/copilot-instructions.md` or `AGENTS.md`.',
          'MCP tool reference: `rails-mcp-tools.mdc`.'
        ]
        lines << 'Repo-specific performance/security: `config/rails_ai_bridge/overrides.md`.' if show_overrides_pointer
        lines << ''
        lines
      end

      # @return [String, nil] raw markdown body from the host app overrides file, or +nil+ if missing,
      #   empty, or still in stub mode (first non-empty line is +<!-- rails-ai-bridge:omit-merge -->+).
      def read_assistant_overrides
        path = resolved_assistant_overrides_path
        return nil unless path && File.file?(path)

        body = File.read(path).strip
        return nil if body.empty?
        return nil unless mergeable_override_content?(body)

        body
      end

      # @return [Boolean] whether overrides are active (merge + Cursor pointer), not placeholder-only
      def overrides_file_exists_and_nonempty?
        read_assistant_overrides != nil
      end

      # @param body [String] trimmed file contents
      # @return [Boolean] +false+ when the install stub has not been activated yet
      def mergeable_override_content?(body)
        first = body.each_line.map(&:strip).find { |line| !line.empty? }
        return false if first.nil?
        return false if OMIT_MERGE_FIRST_LINE.match?(first)

        true
      end

      # @return [String, nil] absolute path to overrides file if Rails app is available
      def resolved_assistant_overrides_path
        return nil unless defined?(Rails) && Rails.application

        base = Rails.application.root.to_s
        cfg = RailsAiBridge.configuration
        raw = cfg.assistant_overrides_path
        if raw.nil? || raw.to_s.empty?
          File.join(base, 'config/rails_ai_bridge/overrides.md')
        else
          p = raw.to_s
          Pathname.new(p).absolute? ? p : File.join(base, p)
        end
      end

      # @return [Array<String>] section to splice after stack; empty if no overrides
      def repo_specific_guidance_section_lines
        body = read_assistant_overrides
        return [] unless body

        [
          '## Repo-specific guidance',
          '',
          body,
          ''
        ]
      end

      # Full-mode Claude Code footer (plain-language bullets; not the compact rules list).
      #
      # @param context [Hash] introspection context (+:conventions+ optional for architecture line)
      # @return [Array<String>] markdown lines (join with newlines for a string)
      def claude_full_footer_lines(context)
        arch = context.dig(:conventions, :architecture)
        arch_summary = arch&.any? ? arch.join(', ') : nil

        lines = [
          '## Behavioral Rules',
          '',
          'When working in this codebase:',
          '- Follow existing patterns and conventions detected above',
          '- Use the database schema as the source of truth for column names and types',
          '- Respect existing associations and validations when modifying models'
        ]
        lines << "- Match the project's architecture style (#{arch_summary})" if arch_summary
        lines << "- Run `#{ContextSummary.test_command(context)}` after making changes to verify correctness"
        lines.concat(RegenerationFooter.continuation_lines(command: 'rails ai:bridge', variant: :context_file))
        lines
      end

      # Closing rules and regeneration footer (shared by compact provider serializers and {Providers::RulesOrchestrator}).
      #
      # @param context [Hash] introspection context (+:conventions+ optional for architecture line)
      # @param rules_heading [String] markdown `## ...` line opening the rules section (default: `## Rules`)
      # @return [Array<String>] markdown lines
      def compact_engineering_rules_footer_lines(context, rules_heading: '## Rules')
        arch = context.dig(:conventions, :architecture)
        arch_summary = arch&.any? ? arch.join(', ') : nil

        lines = [
          rules_heading,
          '',
          '- **Adhere to Conventions:** Strictly follow the existing patterns and conventions outlined in this document.',
          '- **Schema as Source of Truth:** Always use the database schema as the definitive source for column names, types, and relationships.',
          '- **Respect Existing Logic:** Ensure all new code respects existing associations, validations, and service objects.',
          '- **Write Tests:** All new features and bug fixes must be accompanied by corresponding tests.'
        ]
        lines << "- **Match Architecture:** Align with the project's architectural style (#{arch_summary})." if arch_summary
        lines << "- **Verify Correctness:** Run `#{ContextSummary.test_command(context)}` and `bundle exec rubocop` after making changes to ensure correctness and style adherence."
        lines << ''
        lines << '---'
        lines << RegenerationFooter.message_line(command: 'rails ai:bridge', variant: :context_file)
        lines
      end

      # Baseline bullets plus concrete Rails patterns for large data.
      #
      # @return [Array<String>]
      def performance_security_and_rails_examples_lines
        ContextSummary.compact_performance_security_section + rails_performance_examples_lines
      end
    end
  end
end
