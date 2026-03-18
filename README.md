# rails-ai-context

**Turn any Rails app into an AI-ready codebase — one gem install.**

[![CI](https://github.com/crisnahine/rails-ai-context/actions/workflows/ci.yml/badge.svg)](https://github.com/crisnahine/rails-ai-context/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

![Demo](demo.gif?v=0.5.2)

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

This creates:
- `CLAUDE.md` — for Claude Code (with behavioral rules)
- `.cursorrules` — for Cursor (compact rules format)
- `.windsurfrules` — for Windsurf (compact rules format)
- `.github/copilot-instructions.md` — for GitHub Copilot (task-oriented)

Each file is tailored to the AI assistant's preferred format. **Commit these files.** Your entire team gets smarter AI assistance.

### 3. MCP Server (Auto-discovered)

The install generator creates a `.mcp.json` file that Claude Code and Cursor auto-detect — **no manual config needed**. Just open your project.

To start manually:

```bash
rails ai:serve
```

Or configure manually in `~/.claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "my-rails-app": {
      "command": "bundle",
      "args": ["exec", "rails", "ai:serve"],
      "cwd": "/path/to/your/rails/app"
    }
  }
}
```

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
  #   :standard — 8 core introspectors (default, fast)
  #   :full     — all 21 introspectors (thorough)
  config.preset = :standard

  # Or cherry-pick on top of a preset:
  # config.introspectors += %i[views turbo auth api]

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

| AI Assistant | Context File | Format | Command |
|--------------|-------------|--------|---------|
| Claude Code | `CLAUDE.md` | Verbose + behavioral rules | `rails ai:context:claude` |
| Cursor | `.cursorrules` | Compact imperative rules | `rails ai:context:cursor` |
| Windsurf | `.windsurfrules` | Compact imperative rules | `rails ai:context:windsurf` |
| GitHub Copilot | `.github/copilot-instructions.md` | Task-oriented GFM | `rails ai:context:copilot` |
| JSON (generic) | `.ai-context.json` | Structured JSON | `rails ai:context:json` |

---

## Rake Tasks

| Command | Description |
|---------|-------------|
| `rails ai:context` | Generate all context files (skips unchanged) |
| `rails ai:context:claude` | Generate CLAUDE.md only |
| `rails ai:context:cursor` | Generate .cursorrules only |
| `rails ai:context:windsurf` | Generate .windsurfrules only |
| `rails ai:context:copilot` | Generate .github/copilot-instructions.md only |
| `rails ai:context:json` | Generate .ai-context.json only |
| `rails ai:serve` | Start MCP server (stdio, for Claude Code) |
| `rails ai:serve_http` | Start MCP server (HTTP, for remote clients) |
| `rails ai:inspect` | Print introspection summary to stdout |
| `rails ai:doctor` | Run diagnostics and report AI readiness score |
| `rails ai:watch` | Watch for changes and auto-regenerate context files |

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
