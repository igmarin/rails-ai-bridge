# rails-ai-bridge — Best Practices

> For installation and a quick overview, see the [README](../README.md).
> For the full command and configuration reference, see the [Guide](GUIDE.md).

This document consolidates the patterns that consistently produce the best results when using rails-ai-bridge across Cursor, Windsurf, Copilot, Codex, and Claude Code — informed by real-world usage and feedback from multiple AI assistants evaluating the gem.

---

## Table of Contents

- [The Two-Layer System](#the-two-layer-system)
- [Client Compatibility Matrix](#client-compatibility-matrix)
- [Token Optimization](#token-optimization)
- [Keeping Files Fresh](#keeping-files-fresh)
- [Overrides: Teaching the AI Your Team's Conventions](#overrides-teaching-the-ai-your-teams-conventions)
- [Per-Assistant Workflow Tips](#per-assistant-workflow-tips)
- [MCP Drill-Down Workflow](#mcp-drill-down-workflow)
- [Choosing the Right Preset](#choosing-the-right-preset)
- [What to Commit and What to Ignore](#what-to-commit-and-what-to-ignore)

---

## The Two-Layer System

rails-ai-bridge works best as **two complementary layers**, not just one:

| Layer | Mechanism | What it provides |
|-------|-----------|-----------------|
| **Layer 1 — Static files** | `CLAUDE.md`, `.cursor/rules/`, `AGENTS.md`, etc. | Passive project grounding on every session start |
| **Layer 2 — Live MCP** | `rails ai:serve` + `rails_*` tools | On-demand, accurate, live data when needed |

Neither layer alone is optimal:

| Setup | What you get |
|-------|-------------|
| Static files only | Passive overview — can drift with code changes |
| MCP only | Accurate live data — no passive grounding; assistant starts cold |
| **Both (recommended)** | Passive overview + on-demand depth = best coverage |

**Why it matters:** the static file gives the AI the "gut feel" and architectural intuition a human developer builds over days — in a single pass. The MCP layer makes it precise: instead of guessing a column name or route path, the AI calls a tool and gets the current truth.

---

## Client Compatibility Matrix

Each AI client reads different files. Knowing which files matter for your tool helps you understand what gets loaded automatically versus what requires MCP to be running.

| Client | Passive context (always loaded) | Live MCP | Notes |
|--------|---------------------------------|----------|-------|
| **Claude Code** | `CLAUDE.md`, `.claude/rules/*.md` | `.mcp.json` auto-detected | Rules injected per-session; MCP auto-wired via `.mcp.json` |
| **Cursor** | `.cursorrules`, `.cursor/rules/*.mdc` | `.mcp.json` auto-detected | `alwaysApply: true` rules loaded every turn; glob-scoped rules loaded per file |
| **Windsurf / Cascade** | `.windsurfrules`, `.windsurf/rules/*.md` | Manual MCP config required | 6K char limit on `.windsurfrules`; rules directory for overflow |
| **GitHub Copilot (VS Code)** | `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md` | Not supported natively | `applyTo` glob patterns control which instructions file is injected |
| **OpenAI Codex** | `AGENTS.md`, `.codex/README.md` | `.mcp.json` (when configured) | `AGENTS.md` at repo root is the primary context source |
| **Gemini (AI Studio / Code Assist)** | `GEMINI.md` | MCP via Gemini CLI | `GEMINI.md` provides the project briefing; MCP for live data |

### How MCP wiring works per client

- **Claude Code & Cursor**: `.mcp.json` at the project root is auto-detected. Run `rails ai:serve` or let the client spawn it.
- **Windsurf**: MCP servers must be configured manually in Windsurf settings. Add `bundle exec rails ai:serve` as a stdio MCP server.
- **Codex**: Configure in `.codex/mcp_servers.json` or equivalent. The generated `.codex/README.md` includes setup instructions.
- **Copilot**: MCP is not natively supported via `.mcp.json` as of this writing. The `rails_*` tools are documented in `.github/instructions/rails-mcp-tools.instructions.md` but cannot be invoked automatically.

### What "always loaded" means for token budgets

Files marked as `alwaysApply: true` (Cursor) or loaded at session start are included on **every turn**. In long conversations this accumulates. Prefer:

- Short, directive files for always-on context
- Glob-scoped files for model/controller-specific detail (only injected when working on those files)
- MCP tools for deep inspection (only tokens when called)

### Built-in tools and HTTP MCP

There are **11** read-only built-in `rails_*` tools (hosts can add more via configuration). For Hotwire-heavy work, include `:views` and `:stimulus` in your introspectors so `rails_get_view` and `rails_get_stimulus` return live data. If MCP is served over HTTP beyond a locked-down localhost setup, configure authentication and read [mcp-security.md](mcp-security.md) and the repository [SECURITY.md](../SECURITY.md).

---

## Token Optimization

### Prefer glob-scoped rules over always-on rules for detail

```
.cursor/rules/rails-models.mdc       → globs: app/models/**
.cursor/rules/rails-controllers.mdc  → globs: app/controllers/**
.cursor/rules/rails-mcp-tools.mdc    → alwaysApply: true (short reference)
```

The model and controller rules only load when you have those files open — you pay the tokens only when they're relevant.

### Use `detail: "summary"` first with MCP

```ruby
# Step 1 — orient (low cost)
rails_get_schema(detail: "summary")           # → all table names + column counts

# Step 2 — drill into what matters
rails_get_schema(table: "orders")             # → full detail for one table
rails_get_model_details(model: "Order")       # → associations, validations, scopes
```

Requesting full detail for every table at once is almost never necessary and wastes context on data the assistant doesn't need yet.

### Tune list sizes for your app

Large apps can produce models lists that are too long for compact rules. Tune the limits:

```ruby
RailsAiBridge.configure do |config|
  config.copilot_compact_model_list_limit = 10   # default: 15
  config.codex_compact_model_list_limit   = 10
end
```

Set to `0` to omit model names entirely and point only to MCP. This is appropriate when you have 50+ models and the assistant can drill in via tools.

### Avoid duplicating guidance across files

The gem generates content in multiple files to match each client's format. If you add custom rules to `overrides.md`, keep them in **one place** and let the gem merge them — don't manually copy the same rules into `.cursorrules` and `CLAUDE.md`. Duplication increases token cost without improving context quality.

---

## Keeping Files Fresh

Generated files are **snapshots**. They reflect your app at the time you ran `rails ai:bridge`. An AI working from a schema that's 20 commits out of date will still assume the old structure exists.

### When to regenerate

Run `rails ai:bridge` after:

- Adding or removing a model
- Running a migration that changes columns or indexes
- Adding or removing a significant gem
- Changing route structure substantially
- Adding or removing Stimulus controllers or Turbo Streams
- A significant refactor that changes the architecture

**Rule of thumb:** treat `rails ai:bridge` like `bundle install` after a `Gemfile` change — a routine step, not a one-time setup. Commit the regenerated files alongside the code change.

### Auto-regeneration during active development

```bash
rails ai:watch
```

Watches for file changes and regenerates relevant context files automatically. Useful when actively adding models or routes and you want the assistant to track along in the same session.

### Checking if your context is current

```bash
rails ai:doctor
```

The doctor command prints a 0–100 AI readiness score and flags common issues — missing `.mcp.json`, stale context indicators, missing MCP token for production HTTP endpoints, and more.

---

## Overrides: Teaching the AI Your Team's Conventions

The `config/rails_ai_bridge/overrides.md` file is where you add **team-specific rules** that the gem can't infer from code alone. This is one of the most underused features.

### What belongs in overrides.md

Good candidates for overrides:

```markdown
## Team conventions

- All service objects live in `app/services/` and follow the `.call` pattern
- Use `ApplicationRecord.transaction` never ActiveRecord `save!` chains directly
- Background jobs must be idempotent — always check before performing
- All API endpoints must return camelCase JSON (use `camelize` serializer option)
- Prefer `scope` over `where` chains in controllers
- Never use `update_column` — always go through the model's callbacks
```

### Activating overrides

The file ships with a first-line guard that prevents accidental merge:

```
<!-- rails-ai-bridge:omit-merge -->
```

**Delete this line** when you have real rules written. After deleting it, `rails ai:bridge` will merge your overrides into the Copilot and Codex outputs.

For Claude Code and Cursor, your overrides appear in a dedicated section of the generated rules files after merge.

### Warning about the stub

If `overrides.md` still has the omit-merge guard after initial setup, the gem injects **no team-specific guidance** into any client. Run `rails ai:doctor` — it will flag this as a warning if the override file is still a stub.

### overrides.md vs client-specific customization

| What you want | Where to put it |
|---------------|----------------|
| Team-wide conventions (all clients) | `config/rails_ai_bridge/overrides.md` |
| Claude Code-specific guidance | Append to `CLAUDE.md` after regeneration |
| Cursor-specific rules | Add a `.cursor/rules/my-rules.mdc` that won't be overwritten |
| Windsurf-specific | Add a `.windsurf/rules/my-rules.md` that won't be overwritten |

The gem only overwrites files it generated. Files you create with different names are safe.

---

## Per-Assistant Workflow Tips

### Claude Code

1. `CLAUDE.md` + `.claude/rules/` load automatically via the native rules system.
2. `.mcp.json` is auto-detected — no manual MCP setup needed.
3. Use `rails_get_model_details` when writing migrations or associations — Claude Code will call it automatically if the rule instructs it to drill down first.
4. Use `CONTEXT_MODE=full rails ai:bridge:claude` for smaller apps (<30 models) to get richer passive context without MCP.

### Cursor

1. The five `.cursor/rules/*.mdc` files cover different scopes — don't collapse them into one big always-on file.
2. `rails-engineering.mdc` and `rails-project.mdc` are the always-on rules. Keep them concise (< 100 lines each).
3. `rails-models.mdc` and `rails-controllers.mdc` use glob scoping — they only fire when you have model/controller files open.
4. `.cursorrules` is generated for legacy compatibility only. Cursor 0.45+ uses `.cursor/rules/` exclusively. Both can coexist safely.
5. MCP is auto-wired via `.mcp.json`. Run `rails ai:serve` once; Cursor keeps it alive.

### Windsurf / Cascade

1. `.windsurfrules` is capped at ~5,800 characters (Windsurf's 6K limit). The gem respects this — overflow goes into `.windsurf/rules/`.
2. MCP must be configured manually in Windsurf's MCP settings. Add: command `bundle exec rails ai:serve`, cwd: your project path.
3. Cascade is good at following the "summary first, drill down" pattern — the generated `.windsurf/rules/rails-mcp-tools.md` teaches it this workflow.

### GitHub Copilot

1. `.github/copilot-instructions.md` is the primary passive context (capped at 500 lines).
2. `.github/instructions/` files use `applyTo:` glob patterns — they're injected only for relevant files.
3. MCP is not natively supported by Copilot as of this writing. The MCP tool reference in the instructions file documents the tools for when Copilot gains MCP support or you use a different client.
4. Tune `copilot_compact_model_list_limit` to keep the instructions file from growing too large.

### OpenAI Codex

1. `AGENTS.md` is the entry point — Codex reads this at task start.
2. Keep personal preferences in `~/.codex/AGENTS.md`; use the repository `AGENTS.md` for shared guidance.
3. The `.codex/README.md` includes MCP setup instructions for connecting Codex to the live `rails_*` tools.
4. Codex benefits most from explicit conventions (test patterns, service object structure) — make sure `overrides.md` is activated.

### Gemini

1. `GEMINI.md` is the primary briefing file — equivalent to `CLAUDE.md` for the Gemini ecosystem.
2. When using Gemini CLI with MCP support, configure `bundle exec rails ai:serve` as a stdio MCP server.
3. Gemini benefits from directive headers — `GEMINI.md` opens with explicit behavioral rules that tell it how to use the MCP tools.

---

## MCP Drill-Down Workflow

The `rails_*` tools follow a consistent pattern across all clients that support MCP:

```
1. Start broad — use detail: "summary"
   rails_get_schema(detail: "summary")        → all tables, column counts only

2. Identify what matters for the task
   rails_get_schema(table: "users")           → full users table detail

3. Understand the model layer
   rails_get_model_details(model: "User")     → associations, validations, scopes, enums

4. Check routes when needed
   rails_get_routes(controller: "users")      → only routes for this controller

5. Search code for specific patterns
   rails_search_code(pattern: "before_action :authenticate")
```

This pattern is referenced in every generated client file. The assistant learns it passively from the static rules — you don't need to instruct it manually.

### When MCP is unavailable

If the MCP server isn't running (CI, Docker build stages, locked environments), the generated static files still provide a useful baseline. The gem parses `db/schema.rb` as text when no database is connected. The assistant won't have live data but will have the latest committed snapshot.

To verify MCP is operational:

```bash
rails ai:doctor   # flags "MCP server: not running" if it can't reach it
```

---

## Choosing the Right Preset

| Preset | Introspectors | Best for |
|--------|--------------|---------|
| `:standard` (default) | 9 core | Most apps — schema, models, routes, jobs, gems, conventions |
| `:full` | 27 | Full-stack apps where frontend, auth, API, and DevOps context matter |

Add targeted introspectors on top of `:standard` when you only need a few extras:

```ruby
config.preset = :standard
config.introspectors += %i[views auth api tests]
```

The `tests` introspector is particularly valuable — it tells the AI your test framework (RSpec vs Minitest), factory setup (FactoryBot vs fixtures), and CI config. Without it, the AI may generate Minitest assertions in an RSpec project.

---

## What to Commit and What to Ignore

**Commit these** — your whole team benefits:

```
CLAUDE.md
AGENTS.md
GEMINI.md
.cursorrules
.cursor/rules/
.windsurfrules
.windsurf/rules/
.github/copilot-instructions.md
.github/instructions/
.codex/README.md
.mcp.json
config/rails_ai_bridge/overrides.md   ← commit even when stub; remove guard when ready
```

**Ignore these** — generated cache, not useful to commit:

```
.ai-context.json    ← added to .gitignore by the install generator automatically
coverage/
```

The install generator handles `.gitignore` for `.ai-context.json`. The rest are safe to commit. Large teams can add a `rails ai:bridge` step to their onboarding scripts so new developers get fresh context immediately.
