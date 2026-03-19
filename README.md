# rails-ai-context

**Turn any Rails app into an AI-ready codebase — one gem install.**

[![Gem Version](https://badge.fury.io/rb/rails-ai-context.svg)](https://rubygems.org/gems/rails-ai-context)
[![CI](https://github.com/igmarin/rails-ai-context/actions/workflows/ci.yml/badge.svg)](https://github.com/igmarin/rails-ai-context/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Why?

This repository is a fork of the original `crisnahine/rails-ai-context`, maintained by Ismael Marin to add Codex support and fork-specific hardening while preserving the gem's Rails MCP workflow.

You open Claude Code, Cursor, Copilot, or Codex and ask: *"Add a draft status to posts with a scheduled publish date."*

The AI doesn't know your schema, your Devise setup, your Sidekiq jobs, or that `Post` already has an `enum :status`. It generates generic code that doesn't match your app.

**rails-ai-context fixes this.** It auto-introspects your entire Rails app and feeds everything to your AI assistant — schema, models, routes, controllers, jobs, gems, auth, API, tests, config, and conventions — through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io).

**No configuration. No manual tool definitions.** Install this fork from GitHub (see Quick Start), then run the generator.

> **[Full Guide](docs/GUIDE.md)** — complete documentation with every command, parameter, and configuration option.

---

## Quick Start

This fork is installed from GitHub (the `rails-ai-context` gem on RubyGems still points at the upstream release line).

```bash
bundle add rails-ai-context --github=igmarin/rails-ai-context
rails generate rails_ai_context:install
rails ai:context
```

Alternatively, add to your `Gemfile`:

```ruby
gem "rails-ai-context", github: "igmarin/rails-ai-context"
```

Then run `bundle install`, the generator, and `rails ai:context` as above.

That's it. Your AI assistant now understands your entire Rails app.

The install generator creates `.mcp.json` for MCP-capable clients, and `rails ai:context` now generates `AGENTS.md` for Codex-aware workflows.

### Verify the integration in *your* Rails app

1. **`bundle install` must finish cleanly** — until it does, `bundle exec rails -T` and `rails ai:serve` (from `.mcp.json`) cannot be verified. Merging this gem to `main` does not fix a broken or incomplete bundle on the host app.
2. **Regenerate in one shot** — run `rails ai:context` (not only a single format) so route/controller summaries stay consistent across `CLAUDE.md`, `.cursor/rules/`, and `.github/instructions/`.
3. **Keep team-specific rules** — generated files are snapshots. Use **`config/rails_ai_context/overrides.md`** for org-specific constraints (merged only after you **delete the first-line** `<!-- rails-ai-context:omit-merge -->` stub). Until then, the gem does not inject placeholder text into Copilot/Codex. See **`overrides.md.example`** for an outline. Alternatively re-merge into generated files after each `rails ai:context` (see `.codex/README.md`).
4. **Tune list sizes** — `RailsAiContext.configure { |c| c.copilot_compact_model_list_limit = 5 }` (and `codex_compact_model_list_limit`); set `0` to list no model names and point only to MCP.

---

## What Gets Generated

`rails ai:context` generates assistant-specific files tailored to each AI workflow:

```
your-rails-app/
│
├── 🟣 Claude Code
│   ├── CLAUDE.md                                         ≤150 lines (compact)
│   └── .claude/rules/
│       ├── rails-schema.md                               table listing
│       ├── rails-models.md                               model listing
│       └── rails-mcp-tools.md                            full tool reference
│
├── 🟡 OpenAI Codex
│   ├── AGENTS.md                                         project instructions for Codex
│   └── .codex/
│       └── README.md                                     local Codex setup notes
│
├── 🟢 Cursor
│   ├── .cursorrules                                      legacy compat
│   └── .cursor/rules/
│       ├── rails-engineering.mdc                         alwaysApply: true (rules first)
│       ├── rails-project.mdc                             alwaysApply: true
│       ├── rails-models.mdc                              globs: app/models/**
│       ├── rails-controllers.mdc                         globs: app/controllers/**
│       └── rails-mcp-tools.mdc                           alwaysApply: true
│
├── 🔵 Windsurf
│   ├── .windsurfrules                                    ≤5,800 chars (6K limit)
│   └── .windsurf/rules/
│       ├── rails-context.md                              project overview
│       └── rails-mcp-tools.md                            tool reference
│
├── 🟠 GitHub Copilot
│   ├── .github/copilot-instructions.md                   ≤500 lines (compact)
│   └── .github/instructions/
│       ├── rails-models.instructions.md                  applyTo: app/models/**
│       ├── rails-controllers.instructions.md             applyTo: app/controllers/**
│       └── rails-mcp-tools.instructions.md               applyTo: **/*
│
├── 📋 .ai-context.json                                   full JSON (programmatic)
└── .mcp.json                                             MCP auto-discovery
```

Each file respects the AI tool's format and size limits. **Commit these files** so the same project guidance is available to your whole team.

> Use `rails ai:context:full` to dump everything into the files (good for small apps <30 models).

---

## What Your AI Learns

| Category | What's introspected |
|----------|-------------------|
| **Database** | Every table, column, index, foreign key, and migration |
| **Models** | Associations, validations, scopes, enums, callbacks, concerns, macros (`has_secure_password`, `encrypts`, `normalizes`, etc.) |
| **Routing** | Every route with HTTP verbs, paths, controller actions, API namespaces |
| **Controllers** | Actions, filters, strong params, concerns, API controllers |
| **Views** | Layouts, templates, partials, helpers, template engines, view components |
| **Frontend** | Stimulus controllers (targets, values, actions, outlets), Turbo Frames/Streams, model broadcasts |
| **Background** | ActiveJob classes, mailers, Action Cable channels |
| **Gems** | 70+ notable gems categorized (Devise = auth, Sidekiq = jobs, Pundit = authorization, etc.) |
| **Auth** | Devise modules, Pundit policies, CanCanCan, has_secure_password, CORS, CSP |
| **API** | Serializers, GraphQL, versioning, rate limiting, API-only mode |
| **Testing** | Framework, factories/fixtures, CI config, coverage, system tests |
| **Config** | Cache store, session store, middleware, initializers, timezone |
| **DevOps** | Puma, Procfile, Docker, deployment tools, asset pipeline |
| **Architecture** | Service objects, STI, polymorphism, state machines, multi-tenancy, engines |

27 introspectors total. The `:standard` preset runs 9 core ones by default; use `:full` for all 27.

---

## MCP Tools

The gem exposes **9 live tools** via MCP that AI clients call on-demand:

| Tool | What it returns |
|------|----------------|
| `rails_get_schema` | Tables, columns, indexes, foreign keys |
| `rails_get_model_details` | Associations, validations, scopes, enums, callbacks |
| `rails_get_routes` | HTTP verbs, paths, controller actions |
| `rails_get_controllers` | Actions, filters, strong params, concerns |
| `rails_get_config` | Cache, session, timezone, middleware, initializers |
| `rails_get_test_info` | Test framework, factories, CI config, coverage |
| `rails_get_gems` | Notable gems categorized by function |
| `rails_get_conventions` | Architecture patterns, directory structure |
| `rails_search_code` | Ripgrep-powered regex search across the codebase |

All tools are **read-only** — they never modify your application or database.

### Smart Detail Levels

Schema, routes, models, and controllers tools support a `detail` parameter — critical for large apps:

| Level | Returns | Default limit |
|-------|---------|---------------|
| `summary` | Names + counts | 50 |
| `standard` | Names + key details *(default)* | 15 |
| `full` | Everything (indexes, FKs, constraints) | 5 |

```ruby
# Start broad
rails_get_schema(detail: "summary")           # → all tables with column counts

# Drill into specifics
rails_get_schema(table: "users")              # → full detail for one table

# Paginate large schemas
rails_get_schema(detail: "summary", limit: 20, offset: 40)

# Filter routes by controller
rails_get_routes(controller: "users")

# Get one model's full details
rails_get_model_details(model: "User")
```

A safety net (`max_tool_response_chars`, default 120K) truncates oversized responses with hints to use filters.

### Token Savings

The summary-first approach dramatically reduces AI token consumption — especially for large apps:

| Metric | Without gem | Full dump (v0.6) | Smart mode (v0.7+) |
|--------|-------------|------------------|---------------------|
| Context file | 0 tokens | ~15,000 tokens | ~1,500 tokens |
| Schema lookup | manual copy-paste | ~45,000 tokens (all tables) | ~800 tokens (summary) |
| Drill into 1 table | manual copy-paste | included above | ~400 tokens |
| **2-call workflow** | **error-prone** | **~60,000 tokens** | **~2,700 tokens** |

That's **~95% fewer tokens** for the same understanding. The AI gets a compact overview first, then only loads what it actually needs — you pay for precision, not bulk.

**How it saves:**
- Compact context files load ≤150 lines instead of thousands
- `detail:"summary"` gives the AI the full landscape in ~800 tokens
- Specific lookups (`table:`, `model:`, `controller:`) return only what's needed
- Pagination prevents dumping hundreds of tables/routes at once
- Split rule files only activate in relevant directories (e.g., model rules load only when editing `app/models/`)

---

## MCP Server Setup

The install generator creates `.mcp.json` for MCP-capable clients. Claude Code and Cursor can auto-detect it, while Codex can use the generated `AGENTS.md` plus your local Codex configuration.

This fork keeps [`server.json`](server.json) aligned to the fork repository metadata. It intentionally does **not** advertise a packaged registry asset until a fork-specific release artifact exists.

To start manually: `rails ai:serve`

<details>
<summary><strong>Claude Desktop setup</strong></summary>

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS):

```json
{
  "mcpServers": {
    "rails-ai-context": {
      "command": "bundle",
      "args": ["exec", "rails", "ai:serve"],
      "cwd": "/path/to/your/rails/app"
    }
  }
}
```
</details>

<details>
<summary><strong>HTTP transport (for remote clients)</strong></summary>

```bash
rails ai:serve_http  # Starts at http://127.0.0.1:6029/mcp
```

Or auto-mount inside your Rails app:

```ruby
RailsAiContext.configure do |config|
  config.auto_mount = true
  config.http_path  = "/mcp"
end
```

Security note: keep the HTTP transport bound to `127.0.0.1` unless you add your own network and authentication controls. The tools are read-only, but they can still expose sensitive application structure.
</details>

---

## Codex Setup

Codex support in this fork is centered on **`AGENTS.md`** at the repository root.

- Run `rails ai:context:codex` to regenerate `AGENTS.md` and `.codex/README.md`.
- Keep `AGENTS.md` committed so Codex sees project-specific instructions.
- Keep personal preferences in `~/.codex/AGENTS.md`; use the repository `AGENTS.md` for shared guidance.
- When Codex is connected to the generated MCP server, prefer the `rails_*` tools and start with `detail:"summary"`.

---

## Configuration

```ruby
# config/initializers/rails_ai_context.rb
RailsAiContext.configure do |config|
  # Presets: :standard (9 introspectors, default) or :full (all 27)
  config.preset = :standard

  # Cherry-pick on top of a preset
  # config.introspectors += %i[views turbo auth api]

  # Context mode: :compact (≤150 lines, default) or :full (dump everything)
  # config.context_mode = :compact

  # Exclude models from introspection
  config.excluded_models += %w[AdminUser InternalAuditLog]

  # Exclude paths from code search
  config.excluded_paths += %w[vendor/bundle]

  # Cache TTL for MCP tool responses (seconds)
  config.cache_ttl = 30
end
```

<details>
<summary><strong>All configuration options</strong></summary>

| Option | Default | Description |
|--------|---------|-------------|
| `preset` | `:standard` | Introspector preset (`:standard` or `:full`) |
| `introspectors` | 9 core | Array of introspector symbols |
| `context_mode` | `:compact` | `:compact` (≤150 lines) or `:full` (dump everything) |
| `claude_max_lines` | `150` | Max lines for CLAUDE.md in compact mode |
| `max_tool_response_chars` | `120_000` | Safety cap for MCP tool responses |
| `excluded_models` | internal Rails models | Models to skip during introspection |
| `excluded_paths` | `node_modules tmp log vendor .git` | Paths excluded from code search |
| `auto_mount` | `false` | Auto-mount HTTP MCP endpoint |
| `http_path` | `"/mcp"` | HTTP endpoint path |
| `http_port` | `6029` | HTTP server port |
| `cache_ttl` | `30` | Cache TTL in seconds |
</details>

---

## Stack Compatibility

Works with every Rails architecture — auto-detects what's relevant:

| Setup | Coverage | Notes |
|-------|----------|-------|
| Rails full-stack (ERB + Hotwire) | 27/27 | All introspectors relevant |
| Rails + Inertia.js (React/Vue) | ~22/27 | Views/Turbo partially useful, backend fully covered |
| Rails API + React/Next.js SPA | ~20/27 | Schema, models, routes, API, auth, jobs — all covered |
| Rails API + mobile app | ~20/27 | Same as SPA — backend introspection is identical |
| Rails engine (mountable gem) | ~15/27 | Core introspectors (schema, models, routes, gems) work |

Frontend introspectors (views, Turbo, Stimulus, assets) degrade gracefully — they report nothing when those features aren't present.

---

## Commands

| Command | Description |
|---------|-------------|
| `rails ai:context` | Generate all context files (skips unchanged) |
| `rails ai:context:full` | Generate all files in full mode (dumps everything) |
| `rails ai:context:claude` | Generate Claude Code files only |
| `rails ai:context:codex` | Generate Codex files only (`AGENTS.md` + `.codex/README.md`) |
| `rails ai:context:cursor` | Generate Cursor files only |
| `rails ai:context:windsurf` | Generate Windsurf files only |
| `rails ai:context:copilot` | Generate Copilot files only |
| `rails ai:serve` | Start MCP server (stdio) |
| `rails ai:serve_http` | Start MCP server (HTTP) |
| `rails ai:doctor` | Run diagnostics and AI readiness score (0-100) |
| `rails ai:watch` | Auto-regenerate context files on code changes |
| `rails ai:inspect` | Print introspection summary to stdout |

> **Context modes:**
> ```bash
> rails ai:context                              # compact (default) — all formats
> rails ai:context:full                         # full dump — all formats
> CONTEXT_MODE=full rails ai:context:claude     # full dump — Claude only
> CONTEXT_MODE=full rails ai:context:cursor     # full dump — Cursor only
> ```

---

## Works Without a Database

The gem parses `db/schema.rb` as text when no database is connected. Works in CI, Docker build stages, and Claude Code sessions without a running DB.

---

## Requirements

- Ruby >= 3.2, Rails >= 7.1
- [mcp](https://github.com/modelcontextprotocol/ruby-sdk) gem (installed automatically)
- Optional: `listen` gem for watch mode, `ripgrep` for fast code search

---

## vs. Other Ruby MCP Projects

| Project | Approach | rails-ai-context |
|---------|----------|-----------------|
| [Official Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk) | Low-level protocol library | We **use** this as our foundation |
| [fast-mcp](https://github.com/yjacquin/fast-mcp) | Generic MCP framework | We're a **product** — zero-config Rails introspection |
| [rails-mcp-server](https://github.com/maquina-app/rails-mcp-server) | Manual config (`projects.yml`) | We auto-discover everything |

---

## Contributing

```bash
git clone https://github.com/igmarin/rails-ai-context.git
cd rails-ai-context && bundle install
bundle exec rspec       # 350 examples
bundle exec rubocop     # Lint
```

Bug reports and pull requests for this fork are handled at [github.com/igmarin/rails-ai-context](https://github.com/igmarin/rails-ai-context).

## License

[MIT](LICENSE)
