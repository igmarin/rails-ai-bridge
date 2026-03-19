# rails-ai-context

**Turn any Rails app into an AI-ready codebase — one gem install.**

[![Gem Version](https://badge.fury.io/rb/rails-ai-context.svg)](https://rubygems.org/gems/rails-ai-context)
[![CI](https://github.com/crisnahine/rails-ai-context/actions/workflows/ci.yml/badge.svg)](https://github.com/crisnahine/rails-ai-context/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

![Demo](https://raw.githubusercontent.com/crisnahine/rails-ai-context/main/demo.gif)

`rails-ai-context` automatically introspects your Rails application and exposes your models, routes, schema, controllers, views, jobs, gems, auth, API, tests, config, and conventions to AI assistants through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io).

**Your AI assistant instantly understands your entire Rails app. No configuration. No manual tool definitions. Just `bundle add` and go.**

---

## The Problem

You open Claude Code, Cursor, or Copilot in your Rails project and ask: *"Add a draft status to posts with a scheduled publish date."*

The AI doesn't know your schema. It doesn't know you use Devise for auth, Sidekiq for jobs, or that Post already has an `enum :status`. It generates generic code that doesn't match your app's patterns.

## The Solution

```bash
bundle add rails-ai-context
```

That's it. Now your AI assistant knows:

- **Every table, column, index, and foreign key** in your database
- **Every model** with associations, validations, scopes, enums, callbacks, and macros (has_secure_password, encrypts, normalizes, etc.)
- **Every controller** with actions, filters, strong params, and concerns
- **Every view** with layouts, templates, partials, helpers, and template engines
- **Every route** with HTTP verbs, paths, and controller actions
- **Every background job**, mailer, and Action Cable channel
- **Hotwire/Turbo** — Turbo Frames, Turbo Streams, model broadcasts
- **Every notable gem** (70+) and what it means (Devise = auth, Sidekiq = jobs, Turbo = Hotwire)
- **Auth & security** — Devise modules, Pundit policies, CanCanCan, CORS, CSP
- **API layer** — serializers, GraphQL, versioning, rate limiting
- **Test infrastructure** — framework, factories/fixtures, CI config, coverage
- **Configuration** — cache store, session store, middleware, initializers
- **Asset pipeline** — Propshaft/Sprockets, importmaps, CSS framework, JS bundler
- **DevOps** — Puma config, Procfile, Docker, deployment tools
- **Your architecture patterns**: service objects, STI, polymorphism, state machines, multi-tenancy
- **Stimulus controllers** with targets, values, actions, outlets, and classes

---

## Quick Start

### 1. Install

```bash
bundle add rails-ai-context
rails generate rails_ai_context:install
```

### 2. Generate Context Files

```bash
rails ai:context
```

This generates **17 files** — context files and split rule files for each AI assistant:

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
├── 🟢 Cursor
│   ├── .cursorrules                                      legacy compat (compact)
│   └── .cursor/rules/
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
├── 📋 Generic
│   └── .ai-context.json                                  full JSON (programmatic)
│
└── .mcp.json                                             MCP auto-discovery
```

Each file is tailored to the AI assistant's preferred format and respects its size limits. **Commit these files.** Your entire team gets smarter AI assistance.

> **Context modes:** The default `:compact` mode generates small, focused files that point to MCP tools for details. Use `rails ai:context:full` to dump everything into the files instead (good for small apps).

### 3. MCP Server

The gem provides a live MCP server that AI clients can query on-demand for always-up-to-date introspection. Two transports are available:

#### Auto-discovery (recommended)

The install generator creates a `.mcp.json` file in your project root:

```json
{
  "mcpServers": {
    "rails-ai-context": {
      "command": "bundle",
      "args": ["exec", "rails", "ai:serve"]
    }
  }
}
```

**Claude Code** and **Cursor** auto-detect this file — no manual config needed. Just open your project and the MCP tools are available.

#### Manual setup per AI client

<details>
<summary><strong>Claude Code</strong></summary>

Already handled by `.mcp.json` auto-discovery. Or add manually:

```bash
claude mcp add rails-ai-context -- bundle exec rails ai:serve
```
</details>

<details>
<summary><strong>Claude Desktop</strong></summary>

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

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
<summary><strong>Cursor</strong></summary>

Already handled by `.mcp.json` auto-discovery. Or add manually in Cursor Settings > MCP:

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

#### HTTP transport (for remote clients)

For browser-based tools or remote AI clients, use the HTTP transport:

```bash
rails ai:serve_http
```

This starts a standalone HTTP server at `http://127.0.0.1:6029/mcp` using the Streamable HTTP transport.

Or auto-mount it inside your Rails app (no separate process needed):

```ruby
# config/initializers/rails_ai_context.rb
RailsAiContext.configure do |config|
  config.auto_mount = true
  config.http_path  = "/mcp"   # default
end
```

This inserts Rack middleware that handles MCP requests at `/mcp` and passes everything else through to your Rails app.

> **Note:** Both transports are **read-only** — they expose the same 9 introspection tools and never modify your application or database. The stdio transport (`ai:serve`) is recommended for local development; HTTP is for remote or programmatic access.

---

## MCP Tools

The gem exposes 9 tools via MCP that AI clients can call:

| Tool | Description | Annotations |
|------|-------------|-------------|
| `rails_get_schema` | Database schema: tables, columns, indexes, FKs | read-only, idempotent |
| `rails_get_routes` | All routes with HTTP verbs and controller actions | read-only, idempotent |
| `rails_get_model_details` | Model associations, validations, scopes, enums, callbacks | read-only, idempotent |
| `rails_get_gems` | Notable gems categorized by function with explanations | read-only, idempotent |
| `rails_search_code` | Ripgrep-powered code search across the codebase | read-only, idempotent |
| `rails_get_conventions` | Architecture patterns, directory structure, config files | read-only, idempotent |
| `rails_get_controllers` | Controller actions, filters, strong params, concerns | read-only, idempotent |
| `rails_get_config` | App configuration: cache, sessions, middleware, initializers | read-only, idempotent |
| `rails_get_test_info` | Test framework, factories, CI config, coverage | read-only, idempotent |

All tools are **read-only** — they never modify your application or database.

### Detail Levels & Pagination

Tools support a `detail` parameter so AI assistants can start with an overview, then drill into specifics — critical for apps with hundreds of models or tables:

| Detail Level | What it returns | Default limit |
|-------------|-----------------|---------------|
| `summary` | Names + counts (e.g. "users — 12 columns, 3 indexes") | 50 |
| `standard` | Names + key details (e.g. column names and types) | 15 |
| `full` | Everything including indexes, FKs, constraints | 5 |

```
# AI calls summary first to understand the landscape
rails_get_schema(detail: "summary")

# Then drills into a specific table
rails_get_schema(table: "users")

# Pagination for large schemas
rails_get_schema(detail: "summary", limit: 20, offset: 40)
```

Schema and routes tools also support `limit` and `offset` for pagination. A configurable safety net (`max_tool_response_chars`, default 120K) truncates oversized responses with hints to use filters.

## MCP Resources

In addition to tools, the gem registers MCP resources that AI clients can read directly:

| Resource | Description |
|----------|-------------|
| `rails://schema` | Full database schema (JSON) |
| `rails://routes` | All routes (JSON) |
| `rails://conventions` | Detected patterns and architecture (JSON) |
| `rails://gems` | Notable gems with categories (JSON) |
| `rails://controllers` | All controllers with actions and filters (JSON) |
| `rails://config` | Application configuration (JSON) |
| `rails://tests` | Test infrastructure details (JSON) |
| `rails://migrations` | Migration history and statistics (JSON) |
| `rails://engines` | Mounted engines with paths and descriptions (JSON) |
| `rails://models/{name}` | Per-model details (resource template) |

---

## How It Works

```
┌─────────────────────────────────────────┐
│            Your Rails App               │
│                                         │
│  models/  routes  schema  jobs  gems    │
│     │        │       │      │     │     │
│     └────────┴───────┴──────┴─────┘     │
│                  │                       │
│         ┌───────┴────────┐              │
│         │  Introspector  │              │
│         └───────┬────────┘              │
│                 │                        │
│    ┌────────────┼────────────┐          │
│    ▼            ▼            ▼          │
│  CLAUDE.md   MCP Server   .cursorrules  │
│  (static)   (live tools)   (static)     │
└─────────────────────────────────────────┘
         │            │
         ▼            ▼
    Claude Code    Cursor / Windsurf /
    (reads file)   any MCP client
```

**Three modes:**
1. **Static files** (`rails ai:context`) — generates markdown files that AI tools read as project context. Zero runtime cost. Works everywhere.
2. **MCP server** (`rails ai:serve`) — live introspection tools that AI clients call on-demand. Richer, always up-to-date.
3. **Watch mode** (`rails ai:watch`) — auto-regenerates context files when your code changes.

---

## Configuration

```ruby
# config/initializers/rails_ai_context.rb
RailsAiContext.configure do |config|
  # Introspector presets:
  #   :standard — 9 core introspectors (default, fast)
  #   :full     — all 26 introspectors (thorough)
  config.preset = :standard

  # Or cherry-pick on top of a preset:
  # config.introspectors += %i[views turbo auth api]

  # Context mode for generated files (CLAUDE.md, .cursorrules, etc.)
  # :compact — smart, ≤150 lines, references MCP tools (default)
  # :full    — dumps everything into context files (good for small apps)
  # config.context_mode = :compact

  # Max lines for CLAUDE.md in compact mode
  # config.claude_max_lines = 150

  # Max response size for MCP tool results (safety net for large apps)
  # config.max_tool_response_chars = 120_000

  # Exclude internal models from introspection
  config.excluded_models += %w[AdminUser InternalAuditLog]

  # Exclude paths from code search
  config.excluded_paths += %w[vendor/bundle]

  # Auto-mount HTTP MCP endpoint (for remote AI clients)
  # config.auto_mount = true
  # config.http_path  = "/mcp"
  # config.http_port  = 6029

  # Cache TTL for MCP tool responses (seconds)
  config.cache_ttl = 30
end
```

---

## Diagnostics

Check your app's AI readiness:

```bash
rails ai:doctor
```

Reports pass/warn/fail for schema, models, routes, gems, controllers, views, i18n, tests, context files, MCP server, and ripgrep. Includes fix suggestions and an AI readiness score (0-100).

---

## Stimulus Support

The gem automatically detects Stimulus controllers and extracts:
- Controller names (derived from filenames)
- Static targets, values, outlets, and classes
- Action methods

This gives AI assistants context about your frontend JavaScript alongside your backend Ruby.

---

## Supported AI Assistants

| AI Assistant | Main File | Split Rules | Command |
|--------------|-----------|------------|---------|
| Claude Code | `CLAUDE.md` | `.claude/rules/*.md` | `rails ai:context:claude` |
| Cursor | `.cursorrules` | `.cursor/rules/*.mdc` | `rails ai:context:cursor` |
| Windsurf | `.windsurfrules` | `.windsurf/rules/*.md` | `rails ai:context:windsurf` |
| GitHub Copilot | `.github/copilot-instructions.md` | `.github/instructions/*.instructions.md` | `rails ai:context:copilot` |
| JSON (generic) | `.ai-context.json` | — | `rails ai:context:json` |

---

## Stack Compatibility

Works with every Rails architecture — the gem auto-detects what's relevant:

| Setup | Coverage | Notes |
|-------|----------|-------|
| Rails full-stack (ERB + Hotwire) | 27/27 | All introspectors relevant |
| Rails + Inertia.js (React/Vue) | ~22/27 | Views/Turbo partially useful, backend fully covered |
| Rails API + React/Next.js SPA | ~20/27 | Schema, models, routes, API, auth, jobs — all covered |
| Rails API + mobile app | ~20/27 | Same as SPA — backend introspection is identical |
| Rails engine (mountable gem) | ~15/27 | Core introspectors (schema, models, routes, gems) work |

Introspectors that target frontend concerns (views, Turbo, Stimulus, assets) are less relevant for API-only apps, but they degrade gracefully — they simply report nothing when those features aren't present.

> **Tip:** API-only apps can use the `:standard` preset (9 core introspectors) for faster introspection, or cherry-pick with `config.introspectors += %i[auth api]`. See [Configuration](#configuration).

---

## Rake Tasks

| Command | Description |
|---------|-------------|
| `rails ai:context` | Generate all context files + split rules (skips unchanged) |
| `rails ai:context:full` | Generate all files in full mode (dumps everything) |
| `rails ai:context:claude` | Generate CLAUDE.md + .claude/rules/ |
| `rails ai:context:cursor` | Generate .cursorrules + .cursor/rules/ |
| `rails ai:context:windsurf` | Generate .windsurfrules + .windsurf/rules/ |
| `rails ai:context:copilot` | Generate copilot-instructions.md + .github/instructions/ |
| `rails ai:context:json` | Generate .ai-context.json only |
| `rails ai:serve` | Start MCP server (stdio, for Claude Code) |
| `rails ai:serve_http` | Start MCP server (HTTP, for remote clients) |
| `rails ai:inspect` | Print introspection summary to stdout |
| `rails ai:doctor` | Run diagnostics and report AI readiness score |
| `rails ai:watch` | Watch for changes and auto-regenerate context files |

> You can also override context mode via environment variable: `CONTEXT_MODE=full rails ai:context`

> **zsh users:** The bracket syntax `rails ai:context_for[claude]` requires quoting in zsh (`rails 'ai:context_for[claude]'`). The named tasks above (`rails ai:context:claude`) work without quoting in any shell.

---

## Works Without a Database

The gem gracefully degrades when no database is connected — it parses `db/schema.rb` as text. This means it works in:

- CI environments
- Claude Code sessions (no DB running)
- Docker build stages
- Any environment where you have the source code but not a running database

---

## Requirements

- Ruby >= 3.2
- Rails >= 7.1
- [mcp](https://github.com/modelcontextprotocol/ruby-sdk) (official MCP SDK, installed automatically)
- Optional: `listen` gem for watch mode
- Optional: `ripgrep` for fast code search (falls back to Ruby)

---

## vs. Other Ruby MCP Projects

| Project | What it does | How rails-ai-context differs |
|---------|-------------|------------------------------|
| [Official Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk) | Low-level MCP protocol library | We **use** this as our foundation |
| [fast-mcp](https://github.com/yjacquin/fast-mcp) | Generic Ruby MCP framework | We're a **product**, not a framework — zero-config Rails introspection |
| [rails-mcp-server](https://github.com/maquina-app/rails-mcp-server) | Rails MCP server with manual config | We auto-discover everything, no `projects.yml` needed |
| [mcp_on_ruby](https://github.com/rubyonai/mcp_on_ruby) | MCP server with manual tool definitions | We auto-generate tools from your app's structure |

**rails-ai-context is not another MCP SDK.** It's a product that gives your Rails app AI superpowers with one `bundle add`.

---

## Development

```bash
git clone https://github.com/crisnahine/rails-ai-context.git
cd rails-ai-context
bundle install
bundle exec rspec
```

## Contributing

Bug reports and pull requests welcome at https://github.com/crisnahine/rails-ai-context.

## Sponsorship

If rails-ai-context helps your workflow, consider supporting the project — [become a monthly sponsor or buy me a coffee](https://github.com/sponsors/crisnahine).

## License

[MIT License](LICENSE)
