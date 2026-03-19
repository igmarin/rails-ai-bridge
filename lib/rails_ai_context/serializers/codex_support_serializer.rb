# frozen_string_literal: true

module RailsAiContext
  module Serializers
    # Writes optional helper documentation under +.codex/+ (e.g. +README.md+) for team Codex setup notes.
    #
    # Does not replace +AGENTS.md+; use together with {CodexSerializer}.
    #
    # @since 0.8.0
    class CodexSupportSerializer
      attr_reader :context

      # @param context [Hash] Introspection hash; uses +:app_name+ for the generated README.
      def initialize(context)
        @context = context
      end

      # Creates +.codex/README.md+ when content differs from the existing file.
      #
      # @param output_dir [String] Absolute path to the Rails application root (or configured output directory).
      # @return [Hash] +:written+ => array of file paths written, +:skipped+ => array skipped (unchanged content)
      def call(output_dir)
        dir = File.join(output_dir, ".codex")
        FileUtils.mkdir_p(dir)

        filepath = File.join(dir, "README.md")
        content = render_readme

        if File.exist?(filepath) && File.read(filepath) == content
          { written: [], skipped: [ filepath ] }
        else
          File.write(filepath, content)
          { written: [ filepath ], skipped: [] }
        end
      end

      private

      def render_readme
        <<~MD
          # Codex Setup Notes

          This directory contains Codex-specific helper files for `#{context[:app_name]}`.

          ## Recommended setup

          - Keep `AGENTS.md` committed at the repository root. Codex reads it as project guidance.
          - Keep `.mcp.json` committed so MCP-capable clients can discover the Rails MCP server.
          - Start by using the generated `AGENTS.md` guidance, then adjust your local `~/.codex/AGENTS.md` only for personal preferences.

          ## Suggested workflow

          1. Run `rails ai:context` (or `rails ai:context:codex`) after significant schema or architecture changes — a single full run keeps counts consistent across CLAUDE.md, Cursor rules, and Copilot files.
          2. In Codex, prefer the `rails_*` MCP tools over guessing application structure.
          3. Start with `detail:"summary"` and drill down only where needed.

          ## Team rules

          Generated files are **snapshots**. For repo-specific rules (hot tables, auth scoping, required specs), use `config/rails_ai_context/overrides.md`: remove the first-line `<!-- rails-ai-context:omit-merge -->` stub so content is merged into `AGENTS.md` and Copilot. See `overrides.md.example`. Alternatively re-merge curated guidance after each `rails ai:context`.
        MD
      end
    end
  end
end
