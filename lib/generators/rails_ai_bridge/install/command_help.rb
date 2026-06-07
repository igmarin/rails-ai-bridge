# frozen_string_literal: true

module RailsAiBridge
  module Generators
    # Shared mixin that prints the rails-ai-bridge command reference.
    #
    # Included by both {InstallGenerator} (post-install summary) and
    # {HelpGenerator} (on-demand rediscovery) so the two stay in sync from
    # a single source of truth.
    module CommandHelp
      # Prints bridge commands, skill registry commands, bridge-file locations,
      # and MCP discovery note to the terminal.
      #
      # @return [void]
      def print_command_reference
        say 'Bridge commands:', :yellow
        say '  rails ai:bridge                              # Generate all bridge files (compact mode)'
        say '  rails ai:bridge:full                         # Full dump (good for small apps)'
        say '  rails ai:bridge:claude                       # Generate Claude Code files only'
        say '  rails ai:bridge:codex                        # Generate Codex files only'
        say '  rails ai:bridge:cursor                       # Generate Cursor files only'
        say '  rails ai:bridge:windsurf                     # Generate Windsurf files only'
        say '  rails ai:bridge:copilot                      # Generate Copilot files only'
        say '  rails ai:bridge:gemini                       # Generate Gemini files only'
        say '  rails ai:serve                               # Start MCP server (stdio)'
        say '  rails ai:serve_http                          # Start MCP server (HTTP)'
        say '  rails ai:doctor                              # Diagnostics and AI readiness score (0-100)'
        say '  rails ai:watch                               # Auto-regenerate bridge files on code changes'
        say '  rails ai:inspect                             # Print introspection summary to stdout'
        say ''
        say 'Skill registry commands:', :yellow
        say '  rails ai:skills:list                         # Print skill catalog from loaded skill packs'
        say '  rails "ai:skills:resolve[pack,name]"         # Resolve and print a skill\'s full content'
        say '  rails ai:skills:clear_cache                  # Remove locally cached pack repositories'
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
      end
    end
  end
end
