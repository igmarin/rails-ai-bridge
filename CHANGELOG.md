# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Targeting **v2.2.0** when Phase 2–3 and final review are done; gem version remains **2.1.0** until that release tag._

### Added

- **Model semantic classification** — Each ActiveRecord model in introspection output now includes `semantic_tier` (`core_entity`, `pure_join`, `rich_join`, `supporting`) and `semantic_tier_reason` for MCP transparency. Join tables used in `has_many :through` are detected; payload columns beyond FKs and metadata yield `rich_join`.
- **`config.core_models`** — List model class names to tag as `core_entity` for AI-focused context (initializer comment + `Config::Introspection`).
- **`RailsAiBridge::ModelSemanticClassifier`** — PORO that computes tiers from columns, `belongs_to` foreign keys, and through-association membership.
- **`.claude/rules/rails-context.md`** — Semantic layer summary (app metadata + models grouped by tier) for Claude Code, alongside existing split rules.

### Changed

- **Claude rules `rails-models.md`** — Each model line includes `tier: …` when present.
- **`rails_get_model_details` formatters** — Summary, standard, full, and single-model views include semantic tier where applicable.
- **Combustion test setup** — `Combustion.path` is set to `spec/internal`, `Combustion::Database.setup` runs after boot so `:memory:` SQLite has schema before examples, and the internal `ExampleJob` no longer subclasses `ActiveJob::Base` (Active Job is not loaded in the minimal stack).

## [2.1.0] - 2026-04-02

### Added

- **Gemini Support:** Added support for Google's Gemini AI assistant via `GEMINI.md`.
- **New Rake Task:** Added `rails ai:bridge:gemini` to generate Gemini-specific context.
- **Context Harmonization:** Refactored all provider serializers (Claude, Gemini, Codex, Copilot, Cursor, Windsurf) to use a shared `BaseProviderSerializer`.
- **Enhanced AI Guidance:** All context files now feature directive headers, complexity-sorted model lists, and explicit behavioral rules to improve AI code generation.
- **Improved Metadata:** Context files now include descriptions for key config files and standard maintenance commands (e.g., `rubocop`).

### Changed

- **Internal Refactor:** Extracted common rendering logic into `RailsAiBridge::Serializers::Providers::BaseProviderSerializer` to ensure consistency and maintainability across all AI assistants.

## [2.0.0] - 2026-03-31

### Added

- **Shared runtime context provider** — MCP tools and `rails://...` resources now read through `RailsAiBridge::ContextProvider`, keeping cache invalidation and snapshot semantics aligned across both entry points.
- **Explicit extension registries** — `config.additional_introspectors`, `config.additional_tools`, and `config.additional_resources` allow host apps or companion gems to extend the built-ins without patching core constants.
- **HTTP transport Rack builder** — `RailsAiBridge::HttpTransportApp` centralizes HTTP MCP request handling for both standalone server mode and middleware auto-mount.
- **Section-level context reads** — `ContextProvider.fetch_section` and `BaseTool.cached_section` let single-section tools avoid rebuilding or materializing the full snapshot path when unnecessary.
- **Folder-level contributor docs** — key runtime folders now include local `README.md` guides for structure, boundaries, and extension points.
- **Extensibility integration coverage** — specs now prove that a custom introspector, tool, and resource can be registered and used together from the host app configuration surface.
- **Serializer formatter objects** — `MarkdownSerializer` is now a thin orchestrator delegating to 37 single-responsibility `Formatters::*` classes; each formatter is independently testable and injectable.
- **Tool response formatters** — `GetSchema` and `GetModelDetails` delegate all rendering to `Tools::Schema::*` and `Tools::ModelDetails::*` formatter classes; tool `call` methods are ≤20 lines each.
- **`Config::Auth`, `Config::Server`, `Config::Introspection`, `Config::Output`** — `Configuration` is now a `Forwardable` facade over four focused sub-objects; each is independently readable and injectable.
- **`Mcp::Authenticator`** — consolidates strategy resolution, static-token lookup, and configuration predicates into a single entry point, replacing the previous split between `McpHttpAuth` and `Mcp::HttpAuth`.
- **`Mcp::HttpRateLimiter`** — optional in-process sliding-window rate limiter per client IP; configured via `config.mcp.rate_limit_max_requests` and `config.mcp.rate_limit_window_seconds`. Returns 429 with `Retry-After` header when exceeded.
- **`Mcp::HttpStructuredLog`** — optional one-JSON-line-per-request logger for the MCP HTTP path; enabled via `config.mcp.http_log_json = true`. Logs `event`, `http_status`, `path`, `client_ip`, and `request_id`; never logs tokens or full Rack env.
- **`Config::Mcp`** — new `config.mcp` sub-object (5th façade sub-config) for MCP HTTP operational settings: `mode`, `security_profile`, `rate_limit_max_requests`, `rate_limit_window_seconds`, `http_log_json`, `authorize`, `require_auth_in_production`.
- **`config.mcp.authorize`** — optional post-auth lambda `(context, request) { truthy }`; returning falsey yields HTTP 403 on the MCP path.
- **`config.mcp.require_auth_in_production`** — when `true`, boot fails in production unless an auth mechanism is configured.
- **`HttpTransportApp`** updated — request pipeline is now: path check → auth → authorize → rate limit → structured log → transport.
- **`SectionFormatter` template method base** — 22 of 37 formatters now inherit from `SectionFormatter`, which handles the nil/error guard in one place; each formatter only implements `render(data)`.
- **`Serializers::Providers` namespace** — 10 LLM provider serializers extracted into `lib/rails_ai_bridge/serializers/providers/`, separating provider concerns from domain infrastructure (`MarkdownSerializer`, `JsonSerializer`, formatters).
- **`UPGRADING.md`** — new upgrade guide documenting `config.mcp` settings, rate limit semantics, structured logging, `authorize` behaviour, and the `require_auth_in_production` flag.
- **Contributor roadmaps** — `docs/roadmaps.md`, `docs/roadmap-mcp-v2.md`, `docs/roadmap-context-assistants.md` added.

### Changed

- **Install generator messages** — the install flow now reports created vs unchanged files correctly and the generated initializer comments reflect the current preset sizes.
- **Fingerprint reuse on invalidation** — context refresh reuses a single fingerprint snapshot per fetch cycle instead of scanning twice when cached context becomes stale.
- **`FullClaudeSerializer`, `FullRulesSerializer`, `FullCopilotSerializer`, `FullCodexSerializer` removed** — full-mode rendering is now handled by injecting header/footer formatter classes into `MarkdownSerializer` via constructor arguments; no subclassing needed.
- **Test suite expanded to 841 examples at ≥87% line coverage.**

### Fixed

- **Install generator output bug** — `generate_context` results are no longer iterated as raw hash pairs during install-time file generation.
- **`StandardFormatter` pagination hint** — navigation hint now correctly uses `offset + limit < total` (consistent with `SummaryFormatter` and `FullFormatter`), preventing a spurious hint on the last page.

### Upgrading from 1.x

**No configuration changes required.** Every `config.*` attribute from 1.x is still available unchanged — `Configuration` now delegates to focused sub-objects (`Config::Auth`, `Config::Server`, `Config::Introspection`, `Config::Output`, `Config::Mcp`) but exposes the same flat DSL.

The following internal classes were removed; they were never part of the documented public API:

| Removed | Replacement |
|---------|-------------|
| `Mcp::HttpAuth` / `McpHttpAuth` | `Mcp::Authenticator` (same behaviour, single entry point) |
| `FullClaudeSerializer` | Pass `header_class: Formatters::ClaudeHeaderFormatter` to `MarkdownSerializer` |
| `FullCopilotSerializer` | Pass `header_class: Formatters::CopilotHeaderFormatter` to `MarkdownSerializer` |
| `FullCodexSerializer` | Pass `header_class: Formatters::CodexHeaderFormatter` to `MarkdownSerializer` |
| `FullRulesSerializer` | Pass `header_class: Formatters::RulesHeaderFormatter` to `MarkdownSerializer` |

If you were only using the gem through its initializer, rake tasks, or MCP server — no action needed.

## [1.1.0] - 2026-03-20

### Security

- **HTTP MCP authentication** — Optional Bearer token via `config.http_mcp_token` or `ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]` (ENV wins when set). When a token is configured, `auto_mount` and `rails ai:serve_http` require `Authorization: Bearer <token>`.
- **Production guards** — `config.auto_mount = true` in production raises at boot unless `config.allow_auto_mount_in_production = true` and a non-empty MCP token is set. `rails ai:serve_http` in production requires a token.
- **`rails_search_code` allowlist** — `file_type` must be an allowed extension (default: `rb`, `erb`, `js`, `ts`, `jsx`, `tsx`, `yml`, `yaml`, `json`). Extra extensions: `config.search_code_allowed_file_types`. Unrestricted search uses only those extensions; ripgrep/Ruby paths also exclude common secret filenames (e.g. `.env*`, `*.key`, `*.pem`).
- **Credentials metadata** — `credentials_keys` is omitted from config introspection and the `rails://config` MCP resource unless `config.expose_credentials_key_names = true`.

## [1.0.0] - 2026-03-18

### Changed

- **First release as `rails-ai-bridge`** — Ruby gem and GitHub project renamed from `rails-ai-context`; public constant namespace is **`RailsAiBridge`**. Install with `rails generate rails_ai_bridge:install`. Host paths: `config/initializers/rails_ai_bridge.rb`, `config/rails_ai_bridge/overrides.md`, `.mcp.json` server key `rails-ai-bridge`, CLI `exe/rails-ai-bridge`. **Breaking:** no compatibility shim for the old gem name or paths.

### Added

- **`RailsAiBridge::Serializers::SharedAssistantGuidance`** — shared engineering rules, Rails performance pattern examples, optional **`config/rails_ai_bridge/overrides.md`** merge into compact Copilot + Codex, and Cursor `rails-engineering.mdc` body.
- **Cursor `rails-engineering.mdc`** — `alwaysApply: true` engineering essentials + pointers to full `copilot-instructions.md` / `AGENTS.md` and MCP rules.
- **Configuration** — `assistant_overrides_path`, `copilot_compact_model_list_limit` (default 5), `codex_compact_model_list_limit` (default 3); `0` lists no model names (MCP-only pointer).
- **Install generator** — creates `config/rails_ai_bridge/overrides.md` stub and `overrides.md.example` when missing.

### Fixed

- **Overrides stub** — install stub uses `<!-- rails-ai-bridge:omit-merge -->`; overrides are **not** merged into Copilot/Codex until that line is removed.
- **Consistent controller counts in compact output** — stack summaries use the controller introspector for the primary count (aligned with split rules); when routing lists more controller names than `app/controllers` classes, both counts are shown.

### Changed

- **Compact guidance** — `CLAUDE.md`, Copilot compact instructions, and `AGENTS.md` include a performance/security baseline and note that generated files are snapshots; `.codex/README.md` documents re-merging team rules.
- **Copilot compact** — `.github/copilot-instructions.md` leads with **Engineering rules** before stack inventory; MCP section notes path-scoped files under `.github/instructions/` and `.cursor/rules/`.
- **Copilot / Codex / `.cursorrules` order** — engineering rules → stack → optional repo-specific → performance + **Rails patterns** → trimmed models → MCP.
- **Legacy `.cursorrules`** — same ordering; model list uses `copilot_compact_model_list_limit`.
- **`rails-project.mdc`** — uses `ContextSummary.routes_stack_line`; caps gem categories; references `rails-engineering.mdc`.

## [0.8.0] - 2026-03-19

### Added

- **OpenAI Codex support** via `AGENTS.md`, `.codex/README.md`, and `rails ai:context:codex`.
- **Codex serializer integration** in the context file pipeline so `format: :all` now includes Codex output.

### Fixed

- **`rails_search_code` invalid regex handling** — the Ruby fallback path now returns a controlled error response instead of raising `RegexpError`.

### Changed

- **Fork metadata** — gemspec, `server.json`, README, CONTRIBUTING, SECURITY, and CODE_OF_CONDUCT now point to the maintained fork instead of upstream operational contacts.
- **Security documentation** — clarified that MCP tools are read-only but may still expose sensitive application structure, especially over HTTP transport.
- **Internal review summary** — translated `resume.md` to English and updated it to reflect the current fork, Codex support, compatibility notes, and security posture.

## [0.7.1] - 2026-03-19

### Added

- **Full MCP tool reference in all context files** — every generated file (CLAUDE.md, .cursorrules, .windsurfrules, copilot-instructions.md) now includes complete tool documentation with parameters, detail levels, pagination examples, and usage workflow. Dedicated `rails-mcp-tools` split rule files added for Claude, Cursor, Windsurf, and Copilot.
- **MCP Registry listing** — published to the [official MCP Registry](https://registry.modelcontextprotocol.io) as `io.github.crisnahine/rails-ai-context` via mcpb package type.

### Fixed

- **Schema version parsing** — versions with underscores (e.g. `2024_01_15_123456`) were truncated to the first digit group. Now captures the full version string.
- **Documentation** — updated README (detail levels, pagination, generated file tree, config options), SECURITY.md (supported versions), CONTRIBUTING.md (project structure), gemspec (post-install message), demo_script.sh (all 17 generated files).

## [0.7.0] - 2026-03-19

### Added

- **Detail levels on MCP tools** — `detail:"summary"`, `detail:"standard"` (default), `detail:"full"` on `rails_get_schema`, `rails_get_routes`, `rails_get_model_details`, `rails_get_controllers`. AI calls summary first, then drills down. Based on Anthropic's recommended MCP pattern.
- **Pagination** — `limit` and `offset` parameters on schema and routes tools for apps with hundreds of tables/routes.
- **Response size safety net** — Configurable hard cap (`max_tool_response_chars`, default 120K) on tool responses. Truncated responses include hints to use filters.
- **Compact CLAUDE.md** — New `:compact` context mode (default) generates ≤150 lines per Claude Code's official recommendation. Contains stack overview, key models, and MCP tool usage guide.
- **Full mode preserved** — `config.context_mode = :full` retains the existing full-dump behavior. Also available via `rails ai:context:full` or `CONTEXT_MODE=full`.
- **`.claude/rules/` generation** — Generates quick-reference files in `.claude/rules/` for schema and models. Auto-loaded by Claude Code alongside CLAUDE.md.
- **Cursor MDC rules** — Generates `.cursor/rules/*.mdc` files with YAML frontmatter (globs, alwaysApply). Project overview is always-on; model/controller rules auto-attach when working in matching directories. Legacy `.cursorrules` kept for backward compatibility.
- **Windsurf 6K compliance** — `.windsurfrules` is now hard-capped at 5,800 characters (within Windsurf's 6,000 char limit). Generates `.windsurf/rules/*.md` for the new rules format.
- **Copilot path-specific instructions** — Generates `.github/instructions/*.instructions.md` with `applyTo` frontmatter for model and controller contexts. Main `copilot-instructions.md` respects compact mode (≤500 lines).
- **`rails ai:context:full` task** — Dedicated rake task for full context dump.
- **Configurable limits** — `claude_max_lines` (default: 150), `max_tool_response_chars` (default: 120K).

### Changed

- Default `context_mode` is now `:compact` (was implicitly `:full`). Existing behavior available via `config.context_mode = :full`.
- Tools default to `detail:"standard"` which returns bounded results, not unlimited.
- All tools return pagination hints when results are truncated.
- `.windsurfrules` now uses dedicated `WindsurfSerializer` instead of sharing `RulesSerializer` with Cursor.

## [0.6.0] - 2026-03-18

### Added

- **Migrations introspector** — Discovers migration files, pending migrations, recent history, schema version, and migration statistics. Works without DB connection.
- **Seeds introspector** — Analyzes db/seeds.rb structure, discovers seed files in db/seeds/, detects which models are seeded, and identifies patterns (Faker, environment conditionals, find_or_create_by).
- **Middleware introspector** — Discovers custom Rack middleware in app/middleware/, detects patterns (auth, rate limiting, tenant isolation, logging), and categorizes the full middleware stack.
- **Engine introspector** — Discovers mounted Rails engines from routes.rb with paths and descriptions for 23+ known engines (Sidekiq::Web, Flipper::UI, PgHero, ActiveAdmin, etc.).
- **Multi-database introspector** — Discovers multiple databases, replicas, sharding config, and model-specific `connects_to` declarations. Works with database.yml parsing fallback.
- **2 new MCP resources** — `rails://migrations`, `rails://engines`
- **Migrations added to :standard preset** — AI tools now see migration context by default
- **Doctor check** — New `check_migrations` diagnostic
- **Fingerprinter** — Now watches `db/migrate/`, `app/middleware/`, and `config/database.yml`

### Changed

- Default `:standard` preset expanded from 8 to 9 introspectors (added `:migrations`)
- Default `:full` preset expanded from 21 to 26 introspectors
- Doctor checks expanded from 11 to 12
- Static MCP resources expanded from 7 to 9

## [0.5.2] - 2026-03-18

### Fixed

- **MCP tool nil crash** — All 9 MCP tools now handle missing introspector data gracefully instead of crashing with `NoMethodError` when the introspector is not in the active preset (e.g. `rails_get_config` with `:standard` preset)
- **Zeitwerk dependency** — Changed from open-ended `>= 2.6` to pessimistic `~> 2.6` per RubyGems best practices
- **Documentation** — Updated CONTRIBUTING.md, CHANGELOG.md, and CLAUDE.md to reflect Zeitwerk autoloading, introspector presets, and `.mcp.json` auto-discovery changes

## [0.5.0] - 2026-03-18

### Added

- **Introspector presets** — `:standard` (8 core introspectors, fast) and `:full` (all 21, thorough) via `config.preset = :standard`
- **`.mcp.json` auto-discovery** — Install generator creates `.mcp.json` so Claude Code and Cursor auto-detect the MCP server with zero manual config
- **Zeitwerk autoloading** — Replaced 47 `require_relative` calls with Zeitwerk for faster boot and conventional file loading
- **Automated release workflow** — GitHub Actions publishes to RubyGems via trusted publishing when a version tag is pushed
- **Version consistency check** — Release workflow verifies git tag matches `version.rb` before publishing
- **Auto GitHub Release** — Release notes extracted from CHANGELOG.md automatically
- **Dependabot** — Weekly automated dependency and GitHub Actions updates
- **README demo GIF** — Animated terminal recording showing install, doctor, and context generation
- **SECURITY.md** — Security policy with supported versions and reporting process
- **CODE_OF_CONDUCT.md** — Contributor Covenant v2.1
- **GitHub repo topics** — Added discoverability keywords (rails, mcp, ai, etc.)

### Changed

- Default introspectors reduced from 21 to 8 (`:standard` preset) for faster boot; use `config.preset = :full` for all 21
- New files auto-loaded by Zeitwerk — no manual `require_relative` needed when adding introspectors or tools

## [0.4.0] - 2026-03-18

### Added

- **14 new introspectors** — Controllers, Views, Turbo/Hotwire, I18n, Config, Active Storage, Action Text, Auth, API, Tests, Rake Tasks, Asset Pipeline, DevOps, Action Mailbox
- **3 new MCP tools** — `rails_get_controllers`, `rails_get_config`, `rails_get_test_info`
- **3 new MCP resources** — `rails://controllers`, `rails://config`, `rails://tests`
- **Model introspector enhancements** — Extracts `has_secure_password`, `encrypts`, `normalizes`, `delegate`, `serialize`, `store`, `generates_token_for`, `has_one_attached`, `has_many_attached`, `has_rich_text`, `broadcasts_to` via source parsing
- **Stimulus introspector enhancements** — Extracts `outlets` and `classes` from controllers
- **Gem introspector enhancements** — 30+ new notable gems: monitoring (Sentry, Datadog, New Relic, Skylight), admin (ActiveAdmin, Administrate, Avo), pagination (Pagy, Kaminari), search (Ransack, pg_search, Searchkick), forms (SimpleForm), utilities (Faraday, Flipper, Bullet, Rack::Attack), and more
- **Convention detector enhancements** — Detects concerns, validators, policies, serializers, notifiers, Phlex, PWA, encrypted attributes, normalizations
- **Markdown serializer sections** — All 14 new introspector sections rendered in generated context files
- **Doctor enhancements** — 4 new checks: controllers, views, i18n, tests (11 total)
- **Fingerprinter expansion** — Watches `app/controllers`, `app/views`, `app/jobs`, `app/mailers`, `app/channels`, `app/javascript/controllers`, `config/initializers`, `lib/tasks`; glob now covers `.rb`, `.rake`, `.js`, `.ts`, `.erb`, `.haml`, `.slim`, `.yml`

### Fixed

- **YAML parsing** — `YAML.load_file` calls now pass `permitted_classes: [Symbol], aliases: true` for Psych 4 (Ruby 3.1+) compatibility
- **Rake task parser** — Fixed `@last_desc` instance variable leaking between files; fixed namespace tracking with indent-based stack
- **Vite detection** — Changed `File.exist?("vite.config")` to `Dir.glob("vite.config.*")` to match `.js`/`.ts`/`.mjs` extensions
- **Health check regex** — Added word boundaries to avoid false positives on substrings (e.g. "groups" matching "up")
- **Multi-attribute macros** — `normalizes :email, :name` now captures all attributes, not just the first
- **Stimulus action regex** — Requires `method(args) {` pattern to avoid matching control flow keywords
- **Controller respond_to** — Simplified format extraction to avoid nested `end` keyword issues
- **GetRoutes nil guard** — Added `|| {}` fallback for `by_controller` to prevent crash on partial introspection data
- **GetSchema nil guard** — Added `|| {}` fallback for `schema[:tables]` to prevent crash on partial schema data
- **View layout discovery** — Added `File.file?` filter to exclude directories from layout listing
- **Fingerprinter glob** — Changed from `**/*.rb` to multi-extension glob to detect changes in `.rake`, `.js`, `.ts`, `.erb` files

### Changed

- Default introspectors expanded from 7 to 21
- MCP tools expanded from 6 to 9
- Static MCP resources expanded from 4 to 7
- Doctor checks expanded from 7 to 11
- Test suite expanded from 149 to 247 examples with exact value assertions

## [0.3.0] - 2026-03-18

### Added

- **Cache invalidation** — TTL + file fingerprinting for MCP tool cache (replaces permanent `||=` cache)
- **MCP Resources** — Static resources (`rails://schema`, `rails://routes`, `rails://conventions`, `rails://gems`) and resource template (`rails://models/{name}`)
- **Per-assistant serializers** — Claude gets behavioral rules, Cursor/Windsurf get compact rules, Copilot gets task-oriented GFM
- **Stimulus introspector** — Extracts Stimulus controller targets, values, and actions from JS/TS files
- **Database stats introspector** — Opt-in PostgreSQL approximate row counts via `pg_stat_user_tables`
- **Auto-mount HTTP middleware** — Rack middleware for MCP endpoint when `config.auto_mount = true`
- **Diff-aware regeneration** — Context file generation skips unchanged files
- **`rails ai:doctor`** — Diagnostic command with AI readiness score (0-100)
- **`rails ai:watch`** — File watcher that auto-regenerates context files on change (requires `listen` gem)

### Fixed

- **Shell injection in SearchCode** — Replaced backtick execution with `Open3.capture2` array form; added file_type validation, max_results cap, and path traversal protection
- **Scope extraction** — Fixed broken `model.methods.grep(/^_scope_/)` by parsing source files for `scope :name` declarations
- **Route introspector** — Fixed `route.internal?` compatibility with Rails 8.1

### Changed

- `generate_context` now returns `{ written: [], skipped: [] }` instead of flat array
- Default introspectors now include `:stimulus`

## [0.2.0] - 2026-03-18

### Added

- Named rake tasks (`ai:context:claude`, `ai:context:cursor`, etc.) that work without quoting in zsh
- AI assistant summary table printed after `ai:context` and `ai:inspect`
- `ENV["FORMAT"]` fallback for `ai:context_for` task
- Format validation in `ContextFileSerializer` — unknown formats now raise `ArgumentError` with valid options

### Fixed

- `rails ai:context_for[claude]` failing in zsh due to bracket glob interpretation
- Double introspection in `ai:context` and `ai:context_for` tasks (removed unused `RailsAiBridge.introspect` calls)

## [0.1.0] - 2026-03-18

### Added

- Initial release
- Schema introspection (live DB + static schema.rb fallback)
- Model introspection (associations, validations, scopes, enums, callbacks, concerns)
- Route introspection (HTTP verbs, paths, controller actions, API namespaces)
- Job introspection (ActiveJob, mailers, Action Cable channels)
- Gem analysis (40+ notable gems mapped to categories with explanations)
- Convention detection (architecture style, design patterns, directory structure)
- 6 MCP tools: `rails_get_schema`, `rails_get_routes`, `rails_get_model_details`, `rails_get_gems`, `rails_search_code`, `rails_get_conventions`
- Context file generation: CLAUDE.md, .cursorrules, .windsurfrules, .github/copilot-instructions.md, JSON
- Rails Engine with Railtie auto-setup
- Install generator (`rails generate rails_ai_bridge:install`)
- Rake tasks: `ai:context`, `ai:serve`, `ai:serve_http`, `ai:inspect`
- CLI executable: `rails-ai-bridge serve|context|inspect`
- Stdio + Streamable HTTP transport support via official mcp SDK
- CI matrix: Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0
