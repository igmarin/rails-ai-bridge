# Codex Setup Notes

This directory contains Codex-specific helper files for `DemoApp`.

## Recommended setup

- Keep `AGENTS.md` committed at the repository root. Codex reads it as project guidance.
- Keep `.mcp.json` committed so MCP-capable clients can discover the Rails MCP server.
- Start by using the generated `AGENTS.md` guidance, then adjust your local `~/.codex/AGENTS.md` only for personal preferences.

## Suggested workflow

1. Run `rails ai:bridge` (or `rails ai:bridge:codex`) after significant schema or architecture changes — a single full run keeps counts consistent across CLAUDE.md, Cursor rules, and Copilot files.
2. In Codex, prefer the `rails_*` MCP tools over guessing application structure.
3. Start with `detail:"summary"` and drill down only where needed.

## Team rules

Generated files are **snapshots**. For repo-specific rules (hot tables, auth scoping, required specs), use `config/rails_ai_bridge/overrides.md`: remove the first-line `<!-- rails-ai-bridge:omit-merge -->` stub so content is merged into `AGENTS.md` and Copilot. See `overrides.md.example`. Alternatively re-merge curated guidance after each `rails ai:bridge`.
