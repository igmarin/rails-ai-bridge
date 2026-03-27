# frozen_string_literal: true

require "pathname"

module RailsAiBridge
  module Serializers
    # Shared high-signal copy for Copilot, Codex, Cursor, and legacy .cursorrules compact output.
    #
    # @see ContextSummary
    module SharedAssistantGuidance
      module_function

      # First line of +overrides.md+ while in stub mode — file is not merged until removed.
      OMIT_MERGE_FIRST_LINE = /\A<!--\s*rails-ai-bridge:omit-merge\s*-->\z/i

      # Snapshot block for compact AGENTS.md / Copilot: high-level facts from the last introspection run.
      #
      # Composes a fixed heading plus one line per stack, preset, schema/models (when present), routes, and MCP hint.
      #
      # @param context [Hash] introspection snapshot (+:environment+, +:rails_version+, +:schema+, +:models+, …)
      # @return [Array<String>] markdown lines ending with a trailing blank line
      def intro_snapshot_lines(context)
        intro_snapshot_heading_lines + intro_snapshot_metric_lines(context) + [ "" ]
      end

      # Markdown lines for the compact Copilot primary document: full MCP tool cheat sheet (+##+ / +###+ headings).
      #
      # Kept here so +CopilotSerializer+ stays orchestration-only; wording matches split Copilot instruction files.
      #
      # @return [Array<String>]
      def compact_copilot_mcp_tool_reference_lines
        [
          "## MCP Tool Reference",
          "",
          "This project has MCP tools for live introspection.",
          "**Always start with `detail:\"summary\"`, then drill into specifics.**",
          "",
          "### Detail levels (schema, routes, models, controllers)",
          "- `summary` — names + counts (default limit: 50)",
          "- `standard` — names + key details (default limit: 15, this is the default)",
          "- `full` — everything including indexes, FKs (default limit: 5)",
          "",
          "### rails_get_schema",
          "Params: `table`, `detail`, `limit`, `offset`, `format`",
          "- `rails_get_schema(detail:\"summary\")` — all tables with column counts",
          "- `rails_get_schema(table:\"users\")` — full detail for one table",
          "- `rails_get_schema(detail:\"summary\", limit:20, offset:40)` — paginate",
          "",
          "### rails_get_model_details",
          "Params: `model`, `detail`",
          "- `rails_get_model_details(detail:\"summary\")` — list all model names",
          "- `rails_get_model_details(model:\"User\")` — associations, validations, scopes, enums",
          "",
          "### rails_get_routes",
          "Params: `controller`, `detail`, `limit`, `offset`",
          "- `rails_get_routes(detail:\"summary\")` — route counts per controller",
          "- `rails_get_routes(controller:\"users\")` — routes for one controller",
          "",
          "### rails_get_controllers",
          "Params: `controller`, `detail`",
          "- `rails_get_controllers(detail:\"summary\")` — names + action counts",
          "- `rails_get_controllers(controller:\"UsersController\")` — actions, filters, params",
          "",
          "### Other tools",
          "- `rails_get_config` — cache store, session, timezone, middleware",
          "- `rails_get_test_info` — test framework, factories/fixtures, CI config",
          "- `rails_get_gems` — notable gems categorized by function",
          "- `rails_get_conventions` — architecture patterns, directory structure",
          "- `rails_search_code(pattern:\"regex\", file_type:\"rb\", max_results:20)` — codebase search",
          "",
          "_The same MCP reference also appears under `.github/instructions/rails-mcp-tools.instructions.md` and `.cursor/rules/rails-mcp-tools.mdc` for path-scoped clients._",
          ""
        ]
      end

      # @return [Boolean] +true+ when +overrides.md+ exists but is not mergeable (install stub).
      def overrides_stub_active?
        path = resolved_assistant_overrides_path
        return false unless path && File.file?(path)

        body = File.read(path)
        return false if body.strip.empty?

        !mergeable_override_content?(body)
      end

      # @return [Array<String>] markdown lines including heading and trailing blank line
      def compact_engineering_rules_lines
        [
          "## General engineering guidance (rails-ai-bridge baseline)",
          "",
          "_Baseline Rails practices for any app. Team-specific hot tables, auth boundaries, and compliance belong in `config/rails_ai_bridge/overrides.md`._",
          "",
          "### Controllers & strong parameters",
          "- Permit attributes explicitly; never pass raw `params` into `Model.new`, `update`, or `assign_attributes`.",
          "- Extend `permit` lists deliberately when adding fields; mirror neighboring actions in the same controller.",
          "",
          "### Authentication & authorization",
          "- Guard mutating and sensitive reads with the app's existing auth (e.g. `before_action` filters, policies). A public route does not imply public data.",
          "- Use `rails_get_controllers` for filters and `rails_get_conventions` for architecture hints when unsure.",
          "",
          "### Data access & performance",
          "- Avoid N+1: use `includes` / `preload` / `eager_load` for associations used in views or serializers.",
          "- Do not load unbounded collections: paginate list endpoints, use `find_each` in jobs, stream large exports.",
          "- Large or hot tables: check indexes before new `WHERE`/`ORDER BY`; use `rails_get_schema` before heavy queries.",
          "",
          "### Security & inputs",
          "- Treat external input as untrusted; avoid `constantize` / `send` / `eval` on user-controlled strings and raw SQL string interpolation.",
          "- Allow-list host or path for any redirect built from user input (open-redirect risk).",
          "",
          "### Testing",
          "- Prefer request or system specs for HTTP flows and integration; keep model specs tight for business rules.",
          "- Run the project's test suite after substantive edits (often `bundle exec rspec` — confirm framework via `rails_get_test_info`).",
          "",
          "### Repo-specific constraints",
          "- Hot tables, tenant/auth scoping, mandatory spec types, and internal policies belong in `config/rails_ai_bridge/overrides.md`.",
          "- Remove the first-line `<!-- rails-ai-bridge:omit-merge -->` stub marker before that file is merged into Copilot/Codex; use `overrides.md.example` as a starting outline.",
          "",
          "_Regenerated files are snapshots. Re-merge team-specific performance, security, or compliance rules at the top after `rails ai:bridge`, or keep them in separate committed instruction files._",
          ""
        ]
      end

      # Concrete Rails patterns to complement generic performance bullets (gem cannot know your largest tables).
      #
      # @return [Array<String>] markdown lines including heading; no trailing blank line required (caller adds spacing)
      def rails_performance_examples_lines
        [
          "### Rails patterns (large data & hot paths)",
          "- Never use `Model.all` (or unscoped relations) in request cycles — use `where`, `limit`, or pagination.",
          "- Background jobs: iterate with `find_each` or `in_batches` instead of `each` on large relations.",
          "- Prefer `exists?` / `count` with care on huge tables; narrow with `where` first; avoid `length` on loaded associations for big sets.",
          "- Wide rows: fetch only needed columns with `select` / `pluck` when you do not need full records.",
          "- Enable or use `strict_loading` in development/test to catch accidental N+1s early.",
          "- Before adding filters or `ORDER BY` on high-volume tables, confirm indexes via `rails_get_schema` and migrations.",
          ""
        ]
      end

      # Condensed rules for always-on Cursor MDC (stay under ~35 lines of body).
      #
      # @param show_overrides_pointer [Boolean] append pointer to +config/rails_ai_bridge/overrides.md+
      # @return [Array<String>] markdown body lines (no YAML frontmatter)
      def cursor_engineering_mdc_body_lines(show_overrides_pointer: false)
        lines = [
          "# Engineering essentials",
          "",
          "- **Strong params**: permit explicitly; never mass-assign raw `params`.",
          "- **Auth**: protect mutations and sensitive reads; public route ≠ public data.",
          "- **N+1**: `includes` / `preload` / `eager_load` for associations in views and serializers.",
          "- **Bounds**: paginate HTTP lists; `find_each` / `in_batches` in jobs; no `Model.all` in requests.",
          "- **Large tables**: narrow queries; check indexes before new filters/sorts; use `rails_get_schema`.",
          "- **Security**: no `constantize`/`send`/`eval` on user input; no SQL string interpolation; allow-list redirects.",
          "- **Tests**: request/system specs for HTTP; confirm runner with `rails_get_test_info`.",
          "",
          "Generated files are **snapshots** — prefer `rails_*` MCP tools for current structure.",
          "Full engineering rules: `.github/copilot-instructions.md` or `AGENTS.md`.",
          "MCP tool reference: `rails-mcp-tools.mdc`."
        ]
        lines << "Repo-specific performance/security: `config/rails_ai_bridge/overrides.md`." if show_overrides_pointer
        lines << ""
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
          File.join(base, "config/rails_ai_bridge/overrides.md")
        else
          p = raw.to_s
          Pathname.new(p).absolute? ? p : File.join(base, p)
        end
      end

      # @return [Array<String>] merged team rules, stub notice, or optional pointer
      def repo_specific_guidance_section_lines
        body = read_assistant_overrides
        if body
          return [
            "## Repo-specific guidance",
            "",
            body,
            ""
          ]
        end

        if overrides_stub_active?
          return [
            "## Repo-specific guidance",
            "",
            "_Inactive: `config/rails_ai_bridge/overrides.md` still has the `<!-- rails-ai-bridge:omit-merge -->` marker as the first non-empty line. Remove it to merge team rules here._",
            ""
          ]
        end

        path = resolved_assistant_overrides_path
        if path && !File.file?(path)
          return [
            "## Repo-specific guidance",
            "",
            "_Optional: add `config/rails_ai_bridge/overrides.md` for internal constraints (use `overrides.md.example` as a template)._",
            ""
          ]
        end

        []
      end

      # Baseline bullets plus concrete Rails patterns for large data.
      #
      # @return [Array<String>]
      def performance_security_and_rails_examples_lines
        ContextSummary.compact_performance_security_section + rails_performance_examples_lines
      end

      def intro_snapshot_heading_lines
        [
          "## This repository (from introspection)",
          "_Generated by rails-ai-bridge. This is not your team policy file — see **Repo-specific guidance** below._",
          ""
        ]
      end
      private_class_method :intro_snapshot_heading_lines

      def intro_snapshot_metric_lines(context)
        cfg = RailsAiBridge.configuration
        lines = []
        lines << intro_snapshot_stack_bullet(context)
        lines << intro_snapshot_preset_bullet(cfg)
        lines.concat(intro_snapshot_schema_model_bullets(context))
        rline = ContextSummary.routes_stack_line(context)
        lines << rline if rline
        lines << intro_snapshot_mcp_hint_bullet
        lines
      end
      private_class_method :intro_snapshot_metric_lines

      def intro_snapshot_stack_bullet(context)
        env = context[:environment].to_s
        env = "unknown" if env.empty?
        "- **Stack:** Rails #{context[:rails_version]} | Ruby #{context[:ruby_version]} | #{env}"
      end
      private_class_method :intro_snapshot_stack_bullet

      def intro_snapshot_preset_bullet(cfg)
        "- **Preset:** `#{cfg.inferred_preset_name}` (#{cfg.effective_introspectors.size} introspectors; category exclusions applied)"
      end
      private_class_method :intro_snapshot_preset_bullet

      def intro_snapshot_schema_model_bullets(context)
        out = []
        schema = context[:schema]
        if schema.is_a?(Hash) && !schema[:error]
          out << "- **Database:** #{schema[:adapter]} — #{schema[:total_tables]} tables (after `excluded_tables`)"
        end
        models = context[:models]
        if models.is_a?(Hash) && !models[:error]
          out << "- **Models:** #{models.size} (after exclusions)"
        end
        out
      end
      private_class_method :intro_snapshot_schema_model_bullets

      def intro_snapshot_mcp_hint_bullet
        "- **MCP:** start with `rails_get_routes` + `detail:\"summary\"`, then `rails_get_schema` / `rails_get_model_details`."
      end
      private_class_method :intro_snapshot_mcp_hint_bullet
    end
  end
end
