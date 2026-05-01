# rails-ai-bridge — Complete Guide

> Full documentation for [rails-ai-bridge](https://github.com/igmarin/rails-ai-bridge).
> For a quick overview, see the [README](../README.md).

---

## Table of Contents

- [Installation](#installation)
- [Context Modes](#context-modes)
- [Generated Files](#generated-files)
- [All Commands](#all-commands)
- [MCP Tools — Full Reference](#mcp-tools--full-reference)
- [MCP Resources](#mcp-resources)
- [MCP Server Setup](#mcp-server-setup)
- [Configuration — All Options](#configuration--all-options)
- [Introspectors — Full List](#introspectors--full-list)
- [AI Assistant Setup](#ai-assistant-setup)
- [Stack Compatibility](#stack-compatibility)
- [Diagnostics](#diagnostics)
- [Watch Mode](#watch-mode)
- [Works Without a Database](#works-without-a-database)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

---

## Installation

### New project

```bash
bundle add rails-ai-bridge
rails generate rails_ai_bridge:install
rails ai:bridge
```

This creates:
1. `config/initializers/rails_ai_bridge.rb` — configuration file
2. `config/rails_ai_bridge/overrides.md` — stub (omit-merge line); `overrides.md.example` — outline (not merged)
3. `.mcp.json` — MCP auto-discovery for MCP-capable clients
4. Assistant-specific context files — including `AGENTS.md` for Codex

### Existing project

```bash
# Add to Gemfile
gem "rails-ai-bridge"

# Install
bundle install
rails generate rails_ai_bridge:install

# Generate bridge files
rails ai:bridge

# Verify everything works
rails ai:doctor
```

### What the install generator does

1. Creates `.mcp.json` in project root (MCP auto-discovery)
2. Creates `config/initializers/rails_ai_bridge.rb` with commented defaults
3. Creates `config/rails_ai_bridge/overrides.md` (stub) and `overrides.md.example` when absent — remove the omit-merge line from `overrides.md` before real rules are merged
4. Adds `.ai-context.json` to `.gitignore` (JSON cache — markdown files should be committed)
5. Generates all bridge files

---

## Context Modes

The gem has two context modes that control how much data goes into the generated files:

### Compact mode (default)

```bash
rails ai:bridge
```

- CLAUDE.md ≤150 lines
- .windsurfrules ≤5,800 characters
- copilot-instructions.md ≤500 lines
- Files contain a project overview + MCP tool reference
- AI uses MCP tools for detailed data on-demand
- **Best for:** all apps, especially large ones (30+ models)

### Full mode

```bash
rails ai:bridge:full
# or
CONTEXT_MODE=full rails ai:bridge
```

- Dumps everything into context files (schema, all models, all routes, etc.)
- Can produce thousands of lines for large apps
- **Best for:** small apps (<30 models) where the full dump fits in context

### Per-format with mode override

```bash
# Full dump for Claude only, compact for everything else
CONTEXT_MODE=full rails ai:bridge:claude

# Full dump for Cursor only
CONTEXT_MODE=full rails ai:bridge:cursor

# Full dump for Windsurf only (still respects 6K char limit)
CONTEXT_MODE=full rails ai:bridge:windsurf

# Full dump for Copilot only
CONTEXT_MODE=full rails ai:bridge:copilot
```

### Set mode in configuration

```ruby
# config/initializers/rails_ai_bridge.rb
RailsAiBridge.configure do |config|
  config.context_mode = :full  # or :compact (default)
end
```

---

## Generated Files

`rails ai:bridge` generates **19+ files** across all AI assistants (counts include Codex and split rules).

### Claude Code (5 files)

| File | Purpose | Notes |
|------|---------|-------|
| `CLAUDE.md` | Main context file | ≤150 lines in compact mode. Claude Code reads this automatically. |
| `.claude/rules/rails-context.md` | Semantic layer | App metadata + models grouped by `semantic_tier`, ordered by task relevance, plus bounded endpoint focus. In **compact** mode, at most 20 names per tier with an overflow line pointing to `rails_get_model_details`; **full** mode lists all. |
| `.claude/rules/rails-schema.md` | Database table listing | Auto-loaded by Claude Code alongside CLAUDE.md. Adds coarse table-size buckets when `database_stats` is enabled. |
| `.claude/rules/rails-models.md` | Model listing with associations | Includes `tier: …` per ActiveRecord model; adds **Non-ActiveRecord classes (POJO/Service)** for plain Ruby classes under `app/models`. |
| `.claude/rules/rails-mcp-tools.md` | Full MCP tool reference | Parameters, detail levels, pagination, workflow guide. |

### Cursor (6 files)

| File | Purpose | Notes |
|------|---------|-------|
| `.cursorrules` | Legacy context file | Compact mode: engineering rules + stack + MCP (aligned with Copilot order). |
| `.cursor/rules/rails-engineering.mdc` | Engineering essentials | `alwaysApply: true` — strong params, auth, N+1, security; points to overrides + full docs. |
| `.cursor/rules/rails-project.mdc` | Project overview | `alwaysApply: true` — stack counts, endpoint focus, gems (capped), `routes_stack_line`. |
| `.cursor/rules/rails-models.mdc` | Model reference | `globs: app/models/**/*.rb` — auto-attaches when editing models; rows are ordered by task relevance. |
| `.cursor/rules/rails-controllers.mdc` | Controller reference | `globs: app/controllers/**/*.rb` — auto-attaches when editing controllers. |
| `.cursor/rules/rails-mcp-tools.mdc` | MCP tool reference | `alwaysApply: true` — always available. |

### Windsurf (3 files)

| File | Purpose | Notes |
|------|---------|-------|
| `.windsurfrules` | Main context file | Hard-capped at 5,800 chars (Windsurf's 6K limit). Truncated silently if exceeded. |
| `.windsurf/rules/rails-context.md` | Project overview | New Windsurf rules format. |
| `.windsurf/rules/rails-mcp-tools.md` | MCP tool reference | Compact — respects 6K per-file limit. |

### GitHub Copilot (4 files)

| File | Purpose | Notes |
|------|---------|-------|
| `.github/copilot-instructions.md` | Repo-wide instructions | ≤500 lines in compact mode. Order: engineering rules → stack → optional `overrides.md` → performance + Rails patterns → short model list → MCP. |
| `.github/instructions/rails-models.instructions.md` | Model context | `applyTo: app/models/**/*.rb` — loaded when editing models. |
| `.github/instructions/rails-controllers.instructions.md` | Controller context | `applyTo: app/controllers/**/*.rb` — loaded when editing controllers. |
| `.github/instructions/rails-mcp-tools.instructions.md` | MCP tool reference | `applyTo: **/*` — loaded everywhere. |

### Generic (1 file)

| File | Purpose | Notes |
|------|---------|-------|
| `.ai-context.json` | Full structured JSON | For programmatic access or custom tooling. Added to `.gitignore`. |

### Which files to commit

Commit **all files except `.ai-context.json`** (which is gitignored). This gives your entire team AI-assisted context automatically.

### Repo-specific guidance (`config/rails_ai_bridge/overrides.md`)

Optional markdown **merged verbatim** into compact `.github/copilot-instructions.md` and `AGENTS.md` under **Repo-specific guidance** when you run `rails ai:bridge` — **only after** you remove the install stub’s first line: `<!-- rails-ai-bridge:omit-merge -->`. While that line is the first non-empty line in the file, the gem treats overrides as inactive (no placeholder noise in generated files).

- Use **`overrides.md.example`** as a starting outline (that file is never merged).
- Override path: `config.assistant_overrides_path` (relative to `Rails.root` or absolute).
- Cursor does not embed the full file in MDC (size limits); `rails-engineering.mdc` adds a pointer only when mergeable override content exists (stub removed).

The same engineering baseline intentionally appears in Copilot, Codex, and Cursor rules so each client gets local context; change wording once in `SharedAssistantGuidance` in the gem if you maintain a fork.

---

## All Commands

### Context generation

| Command | Mode | Format | Description |
|---------|------|--------|-------------|
| `rails ai:bridge` | compact | all | Generate all bridge files |
| `rails ai:bridge:full` | full | all | Generate all files in full mode |
| `rails ai:bridge:claude` | compact | Claude | CLAUDE.md + .claude/rules/ |
| `rails ai:bridge:codex` | compact | Codex | AGENTS.md + .codex/README.md |
| `rails ai:bridge:cursor` | compact | Cursor | .cursorrules + .cursor/rules/ |
| `rails ai:bridge:windsurf` | compact | Windsurf | .windsurfrules + .windsurf/rules/ |
| `rails ai:bridge:copilot` | compact | Copilot | copilot-instructions.md + .github/instructions/ |
| `rails ai:bridge:json` | — | JSON | .ai-context.json |
| `CONTEXT_MODE=full rails ai:bridge:claude` | full | Claude | Full dump for Claude only |
| `CONTEXT_MODE=full rails ai:bridge:cursor` | full | Cursor | Full dump for Cursor only |
| `CONTEXT_MODE=full rails ai:bridge:windsurf` | full | Windsurf | Full dump for Windsurf only |
| `CONTEXT_MODE=full rails ai:bridge:copilot` | full | Copilot | Full dump for Copilot only |
| `CONFIRM=1 rails ai:bridge` | compact | all | Prompt before overwriting any changed file |

### MCP server

| Command | Transport | Description |
|---------|-----------|-------------|
| `rails ai:serve` | stdio | Start MCP server for Claude Code / Cursor. Auto-discovered via `.mcp.json`. |
| `rails ai:serve_http` | HTTP | Start MCP server at `http://127.0.0.1:6029/mcp`. For remote clients. |

### Utilities

| Command | Description |
|---------|-------------|
| `rails ai:doctor` | Run 12 diagnostic checks. Reports pass/warn/fail with fix suggestions. AI readiness score (0-100). |
| `rails ai:watch` | Watch for file changes and auto-regenerate context files. Requires `listen` gem. |
| `rails ai:inspect` | Print introspection summary to stdout. Useful for debugging. |

### Bracket syntax

```bash
rails 'ai:bridge_for[claude]'    # Requires quoting in zsh
rails ai:bridge:claude           # Use this instead (no quoting needed)
```

### Overwrite confirmation

By default `rails ai:bridge` silently overwrites files whose content has changed. Set `CONFIRM=1` to be prompted before each overwrite:

```bash
CONFIRM=1 rails ai:bridge          # ask before overwriting any changed file
rails ai:bridge                    # silent overwrite (default)
```

Accepted values for `CONFIRM`: `1`, `true`, `yes`, `y`. Any other value (including `CONFIRM=0`, `CONFIRM=false`) keeps the silent default.

You can also control this behaviour programmatically via `RailsAiBridge.generate_context`:

```ruby
RailsAiBridge.generate_context(on_conflict: :skip)    # never overwrite — keep existing
RailsAiBridge.generate_context(on_conflict: :prompt)  # always ask
RailsAiBridge.generate_context(on_conflict: :overwrite) # default — silent replace

# Custom resolver: proc receives the filepath and returns true to allow overwrite
RailsAiBridge.generate_context(
  on_conflict: ->(path) { path.end_with?('CLAUDE.md') }
)
```

| Value | Behaviour |
|-------|-----------|
| `:overwrite` (default) | Silently replaces changed files |
| `:skip` | Keeps existing files even when content differs |
| `:prompt` | Asks interactively before overwriting (requires an interactive TTY) |
| `Proc` / callable | Invoked with the file path; truthy return = overwrite |

### Watch mode — limiting formats

`rails ai:watch` regenerates all formats by default. Restrict to just the formats you actively use to reduce disk writes during active development:

```ruby
# config/initializers/rails_ai_bridge.rb
RailsAiBridge.configure do |config|
  # Regenerates CLAUDE.md + .claude/rules/* and .cursorrules + .cursor/rules/*
  # (split-rule directories are also churned when split_rules: true, the default)
  config.watcher_formats = %i[claude cursor]
end
```

---

## MCP Tools — Full Reference

All **11 built-in tools** are **read-only** and **idempotent** — they never modify your application or database. Hosts can append more via `config.additional_tools`.

### rails_get_schema

Returns database schema: tables, columns, indexes, foreign keys.

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `table` | string | Specific table name for full detail. Omit for listing. |
| `detail` | string | `summary` / `standard` (default) / `full` |
| `limit` | integer | Max tables to return. Default: 50 (summary), 15 (standard), 5 (full). |
| `offset` | integer | Skip tables for pagination. Default: 0. |
| `format` | string | `markdown` (default) / `json` |

**Examples:**

```
rails_get_schema()
  → Standard detail, first 15 tables with column names and types

rails_get_schema(detail: "summary")
  → All tables with column and index counts (up to 50)

rails_get_schema(table: "users")
  → Full detail for users table: columns, types, nullable, defaults, indexes, FKs

rails_get_schema(detail: "summary", limit: 20, offset: 40)
  → Tables 41-60 with column counts

rails_get_schema(detail: "full", format: "json")
  → Full schema as JSON (all tables)
```

### rails_get_model_details

Returns model details: associations, validations, scopes, enums, callbacks, concerns.

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `model` | string | Model class name (e.g. `User`). Case-insensitive. Omit for listing. |
| `detail` | string | `summary` / `standard` (default) / `full`. Ignored when model is specified. |

**Examples:**

```
rails_get_model_details()
  → Standard: all model names with association and validation counts

rails_get_model_details(detail: "summary")
  → Just model names, one per line

rails_get_model_details(model: "User")
  → Full detail: table, associations, validations, enums, scopes, callbacks, concerns, methods

rails_get_model_details(model: "user")
  → Same as above (case-insensitive)

rails_get_model_details(detail: "full")
  → All models with full association lists
```

### rails_get_routes

Returns all routes: HTTP verbs, paths, controller actions, route names.

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `controller` | string | Filter by controller name (e.g. `users`, `api/v1/posts`). Case-insensitive. |
| `detail` | string | `summary` / `standard` (default) / `full` |
| `limit` | integer | Max routes to return. Default: 100 (standard), 200 (full). |
| `offset` | integer | Skip routes for pagination. Default: 0. |

**Examples:**

```
rails_get_routes()
  → Standard: routes grouped by controller with verb, path, action

rails_get_routes(detail: "summary")
  → Route counts per controller with verb breakdown

rails_get_routes(controller: "users")
  → All routes for UsersController

rails_get_routes(controller: "api")
  → All routes matching "api" (partial match, case-insensitive)

rails_get_routes(detail: "full", limit: 50)
  → Full table with route names, first 50 routes

rails_get_routes(detail: "standard", limit: 20, offset: 100)
  → Routes 101-120
```

### rails_get_controllers

Returns controller details: actions, filters, strong params, concerns.

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `controller` | string | Specific controller name (e.g. `UsersController`). Case-insensitive. |
| `detail` | string | `summary` / `standard` (default) / `full`. Ignored when controller is specified. |

**Examples:**

```
rails_get_controllers()
  → Standard: controller names with action lists

rails_get_controllers(detail: "summary")
  → Controller names with action counts

rails_get_controllers(controller: "UsersController")
  → Full detail: parent class, actions, filters (with only/except), strong params

rails_get_controllers(detail: "full")
  → All controllers with actions, filters, and strong params
```

### rails_get_config

Returns application configuration. No parameters.

**Returns:** cache store, session store, timezone, middleware stack, initializers, credentials keys, current attributes.

```
rails_get_config()
  → Cache: redis_cache_store, Session: cookie_store, TZ: UTC, ...
```

### rails_get_test_info

Returns test infrastructure details. No parameters.

**Returns:** test framework (rspec/minitest), factories/fixtures with locations and counts, system tests, CI config, coverage tool, test helpers.

```
rails_get_test_info()
  → Framework: rspec, Factories: spec/factories (12 files), CI: .github/workflows/ci.yml, ...
```

### rails_get_gems

Returns notable gems categorized by function. No parameters.

**Returns:** 70+ recognized gems grouped by category (auth, background_jobs, admin, monitoring, search, pagination, etc.) with versions and descriptions.

```
rails_get_gems()
  → auth: devise (4.9.3), background_jobs: sidekiq (7.2.1), ...
```

### rails_get_conventions

Returns detected architecture patterns. No parameters.

**Returns:** architecture patterns (MVC, service objects, STI, etc.), directory structure with file counts, config files, detected patterns.

```
rails_get_conventions()
  → Architecture: [MVC, Service objects, Concerns], Patterns: [STI, Polymorphism], ...
```

### rails_search_code

Ripgrep-powered regex search across the codebase (Ruby fallback if `rg` is unavailable).

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `pattern` | string | **Required.** Regex pattern to search for. Size capped by `config.search_code_pattern_max_bytes` (default 2048). |
| `path` | string | Optional subdirectory under `Rails.root` (e.g. `app/models`). Default: entire app. |
| `file_type` | string | Filter by file type (e.g. `rb`, `erb`, `js`). Alphanumeric only. Extra types: `config.search_code_allowed_file_types`. |
| `max_results` | integer | Max results to return. Default: **30**, max: 100. |

**Examples:**

```
rails_search_code(pattern: "has_secure_password")
  → All files containing has_secure_password

rails_search_code(pattern: "class.*Controller", file_type: "rb")
  → All Ruby files with controller class definitions

rails_search_code(pattern: "def create", path: "app/controllers", file_type: "rb", max_results: 50)
  → First 50 matches under app/controllers
```

**Security:** Uses `Open3.capture2` with array arguments (no shell injection). Validates `file_type`. Blocks path traversal. Respects `excluded_paths`. Optional wall-clock limit per call: `config.search_code_timeout_seconds` (default 5; set `0` to disable).

### rails_get_view

View-layer context: layouts, templates, partials, helpers, components. Requires the `:views` introspector (included in the `:full` preset, or add `config.introspectors << :views`).

**Parameters:** optional `path` (file under `app/views`), `controller`, `partial`, and `detail` (`summary` / `standard` / `full`).

### rails_get_stimulus

Stimulus controller metadata: targets, values, actions, outlets, classes. Requires the `:stimulus` introspector (included in `:full`, or add `config.introspectors << :stimulus`).

**Parameters:** optional `controller` name and `detail` (`summary` / `standard` / `full`).

### Detail Level Summary

| Level | What it returns | Default limit | Best for |
|-------|----------------|---------------|----------|
| `summary` | Names + counts | 50 | Getting the landscape, understanding what exists |
| `standard` | Names + key details | 15 | Working context, column types, action names |
| `full` | Everything | 5 | Deep inspection, indexes, FKs, constraints |

### Recommended Workflow

1. **Start with `detail:"summary"`** to see what exists
2. **Filter by name** (`table:`, `model:`, `controller:`) for the item you need
3. **Use `detail:"full"`** only when you need indexes, foreign keys, or constraints
4. **Paginate** with `limit` and `offset` for large result sets

---

## MCP Resources

In addition to tools, the gem registers static MCP resources that AI clients can read directly:

| Resource URI | Description |
|-------------|-------------|
| `rails://bridge/meta` | Gem version and enabled feature flags (JSON) |
| `rails://schema` | Full database schema (JSON) |
| `rails://routes` | All routes (JSON) |
| `rails://conventions` | Detected patterns and architecture (JSON) |
| `rails://gems` | Notable gems with categories (JSON) |
| `rails://controllers` | All controllers with actions and filters (JSON) |
| `rails://config` | Application configuration (JSON) |
| `rails://tests` | Test infrastructure details (JSON) |
| `rails://migrations` | Migration history and statistics (JSON) |
| `rails://engines` | Mounted engines with paths and descriptions (JSON) |
| `rails://views` | View-layer summary (JSON); template `rails://views/{path}` |
| `rails://stimulus` | Stimulus summary (JSON); template `rails://stimulus/{name}` |
| `rails://models/{name}` | Per-model details (resource template) |

---

## MCP Server Setup

### Auto-discovery (recommended)

The install generator creates `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "rails-ai-bridge": {
      "command": "bundle",
      "args": ["exec", "rails", "ai:serve"]
    }
  }
}
```

**Claude Code** and **Cursor** auto-detect this file. Codex uses the generated `AGENTS.md` plus your local Codex configuration.

### Claude Code

Auto-discovered via `.mcp.json`. Or add manually:

```bash
claude mcp add rails-ai-bridge -- bundle exec rails ai:serve
```

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "rails-ai-bridge": {
      "command": "bundle",
      "args": ["exec", "rails", "ai:serve"],
      "cwd": "/path/to/your/rails/app"
    }
  }
}
```

### Cursor

Auto-discovered via `.mcp.json`. Or add manually in **Cursor Settings > MCP**:

```json
{
  "mcpServers": {
    "rails-ai-bridge": {
      "command": "bundle",
      "args": ["exec", "rails", "ai:serve"],
      "cwd": "/path/to/your/rails/app"
    }
  }
}
```

### HTTP transport

For browser-based or remote AI clients:

```bash
rails ai:serve_http
# Starts at http://127.0.0.1:6029/mcp
```

Or auto-mount inside your Rails app (no separate process):

```ruby
RailsAiBridge.configure do |config|
  config.auto_mount = true
  config.http_path  = "/mcp"   # default
  config.http_port  = 6029     # default
  config.http_bind  = "127.0.0.1"  # default (localhost only)
end
```

Keep HTTP bound to `127.0.0.1` unless you add your own network and authentication controls. The tools are read-only, but they may still expose sensitive application structure.

Set `config.require_http_auth = true` if the endpoint must not accept anonymous traffic when no Bearer/JWT/static token strategy is configured (returns **401**). Operational notes: [mcp-security.md](mcp-security.md).

### Codex

This fork adds Codex support through `AGENTS.md` and `.codex/README.md`.

- Run `rails ai:bridge:codex` to regenerate Codex guidance.
- Commit `AGENTS.md` for shared repository instructions.
- Keep personal Codex preferences in `~/.codex/AGENTS.md`.

Both transports are **read-only** — they expose the same built-in tools (plus `config.additional_tools`) and never modify your app.

---

## Configuration — All Options

```ruby
# config/initializers/rails_ai_bridge.rb
RailsAiBridge.configure do |config|
  # --- Introspectors ---

  # Presets: :standard (9 core, default) or :full (all 27)
  config.preset = :standard

  # Cherry-pick on top of a preset
  config.introspectors += %i[views turbo auth api]

  # --- Context files ---

  # Context mode: :compact (default) or :full
  config.context_mode = :compact

  # Max lines for CLAUDE.md in compact mode
  config.claude_max_lines = 150

  # Output directory for context files (default: Rails.root)
  # config.output_dir = "/custom/path"

  # Formats regenerated by `rails ai:watch` (default: :all). Narrow to limit churn.
  # config.watcher_formats = %i[claude cursor]

  # --- MCP tools ---

  # Max response size for tool results (safety net)
  config.max_tool_response_chars = 120_000

  # Optional markdown merged into compact Copilot + Codex (default: config/rails_ai_bridge/overrides.md)
  # config.assistant_overrides_path = "config/rails_ai_bridge/overrides.md"

  # Model names shown in compact copilot-instructions / AGENTS / .cursorrules (0 = MCP pointer only)
  # config.copilot_compact_model_list_limit = 5
  # config.codex_compact_model_list_limit = 3

  # Cache TTL for introspection results (seconds)
  config.cache_ttl = 30

  # --- Exclusions ---

  # Models to skip during introspection
  config.excluded_models += %w[AdminUser InternalAuditLog]

  # Primary domain models (semantic tier: core_entity in introspection + Claude rules)
  # config.core_models += %w[User Order Project]

  # Opt-in: Non-ActiveRecord models (POJO/Service classes under app/models)
  # config.introspectors << :non_ar_models

  # Paths to exclude from code search
  config.excluded_paths += %w[vendor/bundle]

  # --- HTTP MCP endpoint ---

  # Auto-mount Rack middleware for HTTP MCP
  config.auto_mount = false
  config.http_path  = "/mcp"
  config.http_bind  = "127.0.0.1"
  config.http_port  = 6029

  # Optional: reject HTTP when no auth strategy is configured (see docs/mcp-security.md)
  # config.require_http_auth = true

  # Code search guardrails
  # config.search_code_pattern_max_bytes = 2048
  # config.search_code_timeout_seconds = 5.0  # 0 disables timeout

  # Nested MCP HTTP options (rate limit profile, post-auth authorize, etc.)
  # config.mcp.security_profile = :balanced  # :strict | :balanced | :relaxed
  # config.mcp.authorize = ->(_context, _request) { true }
end
```

### Options reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `preset` | Symbol | `:standard` | Introspector preset (`:standard` or `:full`) |
| `introspectors` | Array | 9 core symbols | Which introspectors to run |
| `context_mode` | Symbol | `:compact` | `:compact` or `:full` |
| `claude_max_lines` | Integer | `150` | Max lines for CLAUDE.md in compact mode |
| `max_tool_response_chars` | Integer | `120_000` | Safety cap for MCP tool responses |
| `cache_ttl` | Integer | `30` | Cache TTL in seconds for introspection results |
| `excluded_models` | Array | internal Rails models | Models to skip |
| `core_models` | Array | `[]` | Model names tagged as `core_entity` in introspection output and `.claude/rules/rails-context.md`. Used by `RailsAiBridge::ModelSemanticClassifier` to mark primary domain models. |
| `introspectors` | Array | 9 core symbols | Which introspectors to run. Add `:non_ar_models` to include non-ActiveRecord classes under `app/models`. |
| `excluded_paths` | Array | `node_modules tmp log vendor .git` | Paths excluded from code search |
| `output_dir` | String | `nil` (Rails.root) | Where to write context files |
| `auto_mount` | Boolean | `false` | Auto-mount HTTP MCP endpoint |
| `http_path` | String | `"/mcp"` | HTTP endpoint path |
| `http_bind` | String | `"127.0.0.1"` | HTTP bind address |
| `http_port` | Integer | `6029` | HTTP server port |
| `require_http_auth` | Boolean | `false` | HTTP **401** when no MCP auth strategy configured |
| `search_code_pattern_max_bytes` | Integer | `2048` | Max `rails_search_code` pattern size |
| `search_code_timeout_seconds` | Float | `5.0` | Per-search wall clock (`0` = off) |
| `rate_limit_max_requests` | Integer / nil | profile | Per-IP HTTP limit (`0` disables); not shared across workers |
| `rate_limit_window_seconds` | Integer | `60` | Sliding window for rate limit |
| `http_log_json` | Boolean | `false` | Structured JSON log line per HTTP MCP response |
| `server_name` | String | `"rails-ai-bridge"` | MCP server name |
| `assistant_overrides_path` | String | `nil` → `config/rails_ai_bridge/overrides.md` | Markdown merged into compact Copilot + Codex |
| `copilot_compact_model_list_limit` | Integer | `5` | Max model rows in copilot-instructions / `.cursorrules` (`0` = none) |
| `codex_compact_model_list_limit` | Integer | `3` | Max model rows in `AGENTS.md` (`0` = none) |
| `watcher_formats` | Symbol / Array | `:all` | Formats regenerated by `rails ai:watch`. Set to e.g. `%i[claude cursor]` to skip formats you don't use during active development. |

---

## Introspectors — Full List

### Standard preset (9 introspectors)

These run by default. Fast and cover core Rails structure.

| Introspector | What it discovers |
|-------------|-------------------|
| `schema` | Tables, columns, types, indexes, foreign keys, primary keys. Falls back to `db/schema.rb` parsing when no DB connected. |
| `models` | Associations, validations, scopes, enums, callbacks, concerns, instance methods, class methods. Source-level macros: `has_secure_password`, `encrypts`, `normalizes`, `delegate`, `serialize`, `store`, `generates_token_for`, `has_one_attached`, `has_many_attached`, `has_rich_text`, `broadcasts_to`. **Semantic tier** per model: `core_entity` (from `config.core_models`), `pure_join` / `rich_join` (through join tables), or `supporting`. |
| `routes` | All routes with HTTP verbs, paths, controller actions, route names, API namespaces, mounted engines. |
| `jobs` | ActiveJob classes with queue names. Mailers with action methods. Action Cable channels. |
| `gems` | 70+ notable gems categorized: auth, background_jobs, admin, monitoring, search, pagination, forms, file_upload, testing, linting, security, api, frontend, utilities. |
| `conventions` | Architecture patterns (MVC, service objects, STI, polymorphism, etc.), directory structure with file counts, config files, detected patterns. |
| `controllers` | Actions, filters (before/after/around with only/except), strong params methods, parent class, API controller detection, concerns. |
| `tests` | Test framework (rspec/minitest), factories/fixtures with locations and counts, system tests, CI config files, coverage tool, test helpers, VCR cassettes. |
| `migrations` | Total count, schema version, pending migrations, recent migration history with detected actions (create_table, add_column, etc.), migration statistics. |

**Standard opt-in:** `non_ar_models` — Ruby classes under `app/models` that are not subclasses of `ActiveRecord::Base`, tagged **`[POJO/Service]`** in `rails_get_model_details` listings and Claude `rails-models.md`. Included in `:full`; add it manually when staying on `:standard`. Uses `Object.const_source_location` after eager load.

### Full preset (27 introspectors)

Includes all standard introspectors plus:

| Introspector | What it discovers |
|-------------|-------------------|
| `non_ar_models` | Ruby classes under `app/models` that are not subclasses of `ActiveRecord::Base`, tagged **`[POJO/Service]`** in model listings. |
| `stimulus` | Stimulus controllers with targets, values (with types), actions, outlets, classes. Extracted from JS/TS files. |
| `views` | Layouts, templates grouped by controller, partials (per-controller and shared), helpers with methods, template engines (erb, haml, slim), view components. |
| `turbo` | Turbo Frames (IDs and files), Turbo Stream templates, model broadcasts (`broadcasts_to`, `broadcasts`). |
| `i18n` | Default locale, available locales, locale files with key counts, backend class, parse errors. |
| `config` | Cache store, session store, timezone, middleware stack, initializers, credentials keys, CurrentAttributes classes. |
| `active_storage` | Attachments (has_one_attached, has_many_attached per model), storage services, direct upload config. |
| `action_text` | Rich text fields (has_rich_text per model), Action Text installation status. |
| `auth` | Devise models with modules, Rails 8 built-in auth, has_secure_password, Pundit policies, CanCanCan, CORS config, CSP config. |
| `api` | API-only mode, API versioning (from directory structure), serializers (Jbuilder, AMS, etc.), GraphQL (types, mutations), rate limiting (Rack::Attack). |
| `rake_tasks` | Custom rake tasks in `lib/tasks/` with names, descriptions, namespaces, file paths. |
| `assets` | Asset pipeline (Propshaft/Sprockets), JS bundler (importmap/esbuild/webpack/vite), CSS framework, importmap pins, manifest files. |
| `devops` | Puma config (threads, workers, port), Procfile entries, Docker (multi-stage detection), deployment tools, health check routes. |
| `action_mailbox` | Action Mailbox mailboxes with routing patterns. |
| `seeds` | db/seeds.rb analysis (Faker usage, environment conditionals), seed files in db/seeds/, models seeded. |
| `middleware` | Custom Rack middleware in app/middleware/ with detected patterns (auth, rate limiting, tenant isolation, logging). Full middleware stack. |
| `engines` | Mounted Rails engines from routes.rb with paths and descriptions for 23+ known engines (Sidekiq::Web, Flipper::UI, PgHero, ActiveAdmin, etc.). |
| `multi_database` | Multiple databases, replicas, sharding config, model-specific `connects_to` declarations. database.yml parsing fallback. |
| `database_stats` | PostgreSQL approximate row counts via `pg_stat_user_tables`, bucketed as `small`, `medium`, `large`, or `hot`. Opt-in only, requires PostgreSQL. |

### Enabling the full preset

```ruby
config.preset = :full
```

### Cherry-picking introspectors

```ruby
# Start with standard, add specific ones
config.introspectors += %i[views turbo auth api stimulus]

# Or build from scratch
config.introspectors = %i[schema models routes gems auth api]
```

---

## AI Assistant Setup

### Claude Code

**Auto-discovery:** Opens `.mcp.json` automatically. No setup needed.

**Context files loaded:**
- `CLAUDE.md` — read at conversation start
- `.claude/rules/*.md` — auto-loaded alongside CLAUDE.md

**MCP tools:** Available immediately via `.mcp.json`.

### Cursor

**Auto-discovery:** Opens `.mcp.json` automatically. No setup needed.

**Context files loaded:**
- `.cursorrules` — read at conversation start
- `.cursor/rules/*.mdc` — loaded based on `alwaysApply` and `globs` settings

**MDC rule activation modes:**
| Mode | When it activates |
|------|-------------------|
| `alwaysApply: true` | Every conversation (project overview, MCP tools) |
| `globs: ["app/models/**/*.rb"]` | When editing files matching the glob pattern |
| `alwaysApply: false` + `description` | When the AI decides it's relevant based on description |

### Windsurf

**Context files loaded:**
- `.windsurfrules` — read at conversation start (≤6,000 chars, silently truncated if exceeded)
- `.windsurf/rules/*.md` — new rules format

**Limits:**
- 6,000 characters per rule file
- 12,000 characters total (global + workspace combined)

### GitHub Copilot

**Context files loaded:**
- `.github/copilot-instructions.md` — repo-wide instructions
- `.github/instructions/*.instructions.md` — path-specific, activated by `applyTo` glob

**applyTo patterns:**
| Pattern | When it activates |
|---------|-------------------|
| `app/models/**/*.rb` | Editing model files |
| `app/controllers/**/*.rb` | Editing controller files |
| `**/*` | All files (MCP tool reference) |

---

## Stack Compatibility

| Setup | Coverage | Notes |
|-------|----------|-------|
| Rails full-stack (ERB + Hotwire) | 27/27 | All introspectors relevant |
| Rails + Inertia.js (React/Vue) | ~22/27 | Views/Turbo partially useful, backend fully covered |
| Rails API + React/Next.js SPA | ~20/27 | Schema, models, routes, API, auth, jobs — all covered |
| Rails API + mobile app | ~20/27 | Same as SPA — backend introspection is identical |
| Rails engine (mountable gem) | ~15/27 | Core introspectors (schema, models, routes, gems) work |

Frontend introspectors (views, Turbo, Stimulus, assets) degrade gracefully — they report nothing when those features aren't present.

**Tip for API-only apps:**

```ruby
# Use standard preset (already perfect for API apps)
config.preset = :standard

# Or add API-specific introspectors
config.introspectors += %i[auth api]
```

---

## Diagnostics

```bash
rails ai:doctor
```

Runs 12 checks and reports an AI readiness score (0-100):

| Check | What it verifies |
|-------|------------------|
| Schema | db/schema.rb exists and is parseable |
| Models | Model files detected in app/models/ |
| Routes | Routes are mapped |
| Gems | Gemfile.lock exists and is parseable |
| Controllers | Controller files detected |
| Views | View templates detected |
| I18n | Locale files exist |
| Tests | Test framework detected |
| Migrations | Migration files exist |
| Context files | Generated context files exist |
| MCP Server | MCP server can be built |
| Ripgrep | `rg` binary installed (optional, falls back to Ruby) |

Each check reports **pass**, **warn**, or **fail** with fix suggestions.

---

## Watch Mode

Auto-regenerate context files when your code changes:

```bash
rails ai:watch
```

Requires the `listen` gem:

```ruby
# Gemfile
gem "listen", group: :development
```

Watches for changes in: `app/`, `config/`, `db/`, `lib/tasks/`, and regenerates only the files that changed (diff-aware, skips unchanged files).

---

## Works Without a Database

The gem gracefully degrades when no database is connected. The schema introspector parses `db/schema.rb` as text instead of querying `information_schema`.

Works in:
- CI/CD pipelines
- Claude Code sessions (no DB running)
- Docker build stages
- Read-only environments
- Any environment with source code but no running database

---

## Security

- All MCP tools are **read-only** — they never modify your application or database
- Code search uses `Open3.capture2` with array arguments — **no shell injection**
- File paths are validated against **path traversal** attacks
- Credentials and secret values are **never exposed** — only key names are introspected (unless you opt in with `expose_credentials_key_names`)
- Generated config-file listings and the `rails://conventions` MCP resource omit secret-bearing paths such as `.env*`, Rails credentials files, secret/private directories, `master.key`, and private key material
- The gem makes **no outbound network requests**
- File type validation prevents arbitrary file access in code search
- `max_results` is capped at 100 to prevent resource exhaustion; `pattern` length is capped (`search_code_pattern_max_bytes`); optional per-invocation timeout (`search_code_timeout_seconds`)
- Invalid regex input in the Ruby fallback path returns a controlled error response
- HTTP MCP can require a configured auth strategy (`require_http_auth`) — see [mcp-security.md](mcp-security.md) and [SECURITY.md](../SECURITY.md)
- Read-only access can still expose sensitive application structure; treat generated files and MCP responses as internal artifacts

---

## Troubleshooting

### MCP server not detected by Claude Code / Cursor

1. Check `.mcp.json` exists in project root
2. Verify it contains `"command": "bundle"` and `"args": ["exec", "rails", "ai:serve"]`
3. Restart Claude Code / Cursor

### Context files are too large

```ruby
# Switch to compact mode (default in v0.7+)
config.context_mode = :compact
```

### MCP tool responses are too large

```ruby
# Lower the safety cap
config.max_tool_response_chars = 60_000
```

### Schema not detected

- Ensure `db/schema.rb` exists (run `rails db:schema:dump` if needed)
- The gem works without a database — it parses schema.rb as text

### Models not detected

- Models must be in `app/models/` and inherit from `ApplicationRecord`
- Excluded models: `ApplicationRecord`, `ActiveStorage::*`, `ActionText::*`, `ActionMailbox::*`
- Add custom exclusions: `config.excluded_models += %w[InternalModel]`

### Ripgrep not found

Code search falls back to Ruby's `Dir.glob` + `File.read`. Install ripgrep for faster search:

```bash
# macOS
brew install ripgrep

# Ubuntu/Debian
sudo apt install ripgrep
```

### Watch mode not working

```bash
# Install listen gem
bundle add listen --group development

# Then run
rails ai:watch
```

### Tool responses show "not available"

The tool's introspector isn't in the active preset. Either:

```ruby
# Use full preset
config.preset = :full

# Or add the specific introspector
config.introspectors += %i[config]  # for rails_get_config
config.introspectors += %i[tests]   # for rails_get_test_info
```
