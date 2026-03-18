# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- Double introspection in `ai:context` and `ai:context_for` tasks (removed unused `RailsAiContext.introspect` calls)

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
- Install generator (`rails generate rails_ai_context:install`)
- Rake tasks: `ai:context`, `ai:serve`, `ai:serve_http`, `ai:inspect`
- CLI executable: `rails-ai-context serve|context|inspect`
- Stdio + Streamable HTTP transport support via official mcp SDK
- CI matrix: Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0
