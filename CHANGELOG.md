# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.6.0]

### Changed

- **`mcp` minimum version raised to 0.25** (#92) — the gemspec lower bound is now `>= 0.25` (was `>= 0.10`), matching the minimum version the codebase actually requires. The upper bound remains `< 1.0`.
- **`rubydex` constraint tightened to `~> 0.2.9`** (#92) — was `~> 0.2.4`. This is a **minor breaking change** for users pinned to rubydex 0.2.4–0.2.8; update your lockfile with `bundle update rubydex`.
- **`simplecov` bumped to 1.0** (#92) — development dependency only; does not affect gem consumers. The test suite filter was migrated from `add_filter '/spec/'` to `skip 'spec'` per the simplecov 1.0 migration guide (`SourceFile#project_filename` no longer includes a leading separator).

### Fixed

- **`Style/ArrayIntersect` lint offense** (#91/#92) — pre-existing rubocop offense in `context_summary.rb` autocorrected to use `Array#intersect?`. No behavior change.

### Added

- **PathResolver architectural documentation** (#90/#91) — class-level docblock documents PathResolver's intentional role as a shared utility (11 introspector callers, high betweenness centrality). Prevents false "god class" flags from future graph analyses.
- **PathResolver edge-case tests** (#90/#91) — 6 new specs covering the private `SafeRelativePath` (backslash normalization, Windows path rejection, empty path rejection) and `SafeJoin` (valid joins, traversal escape prevention) helper classes.

## [3.5.2]

### Security

- **HTTP MCP unauthenticated boot warning** (#60/#81) — the standalone HTTP MCP server now prints a one-time stderr warning when it boots in a non-production environment without an authentication strategy, making the default open behavior visible.
- **Pluggable / distributed rate limiting** (#69/#80) — `config.mcp.rate_limiter` accepts any object implementing `allow?(ip)` or `call(ip)`, enabling shared backends such as Redis or `Rails.cache`. A built-in `Mcp::CacheRateLimiter` is provided for multi-process Puma deployments.
- **Skill pack lockfile verification** (#65/#84) — `config/rails_ai_bridge/directory.lock` records the expected git commit SHA for every remote skill pack. `PackResolver` compares the cloned HEAD against the lockfile and fails closed on mismatch. Generate or update the lockfile with `rails ai:registry:lockfile`. Verification mode is configurable via `config.registry.lockfile_verification` (`:strict`, `:warn`, `:disabled`).
- **Security documentation** (#61/#62/#82/#83) — added distributed rate-limiting guidance, a stdio transport threat model, and operational hardening recommendations.

### Added

- **CORS support for HTTP MCP** (#63/#76) — `config.mcp.cors_origins` controls `Access-Control-Allow-Origin` headers for the MCP HTTP endpoint; `['*']` or a list of exact origins is supported.
- **JSON output for MCP tools** (#68/#77) — `rails_get_routes` and `rails_get_model_details` now accept `format: 'json'` for programmatic clients.
- **`authorize` lambda logging** (#64/#75) — explicit denies and lambda exceptions on the HTTP MCP path are now logged and emitted through `Mcp::HttpStructuredLog`.
- **`bundler-audit` CI job** (#74/#78) — the GitHub Actions workflow now runs `bundle-audit update && bundle-audit check` to catch known vulnerable dependencies.
- **MCP tool result caching** (#71/#79) — opt-in TTL-based cache keyed by tool name + SHA256 fingerprint of arguments. Enable with `config.mcp.tool_result_cache_ttl` (default `0`).
- **ActiveSupport::Notifications hooks** (#72/#85) — emits `rails_ai_bridge.tool.call`, `rails_ai_bridge.tool.result_cache_hit/miss`, `rails_ai_bridge.auth.success/failure`, and `rails_ai_bridge.rate_limit.hit` events.
- **Rails 8.1+ introspection signals** (#73/#86) — `GemRegistry` now recognizes `mission_control-jobs`; `ConfigIntrospector` reports `queue_adapter` and `cable_adapter`; `AuthIntrospector` surfaces Rails 8 generator patterns (`authentication_concern`, `generates_token_for`, `normalizes`).

### Changed

- **Summary-first defaults** (#70/#87) — `rails_get_schema` and `rails_get_model_details` now default to `detail: 'summary'` when listing, reducing the chance of oversized tool responses. Callers can still opt into `standard` or `full` and use filters for specific tables/models.

### Tests

- **Total: 2157 examples, 0 failures, 94.34% line coverage**.

## [3.5.1]

### Security

- Harden `DefaultGitRunner` git commands against option injection by validating clone URL/destination and using `--` separators for `git clone`; add `nosemgrep` suppressions for documented false positives in `git pull` and `git checkout`.
- Add `protect_from_forgery` to all test/fixture `ApplicationController` classes.
- Replace `content_tag` with `tag.h1` in the internal test `ApplicationHelper` and rename the misleading `raw` variable in `Config::Mcp`.
- Add `nosemgrep` comments with explanatory notes for unscoped-find false positives in internal test controllers.
- Harden `rails_search_code` ripgrep command with a `--` separator and replace shell-based `which rg` detection with direct `rg --version` checks.

## [3.5.0]

### Added

- **`git_timeout` for git operations** — `Config::Registry#git_timeout` (default `30` seconds) is
  now passed to `DefaultGitRunner`, which wraps every git subprocess (`clone`, `pull`, `checkout`)
  in `Timeout.timeout`. A slow or unreachable remote can no longer block the calling thread
  indefinitely; a descriptive `RuntimeError` (e.g. `"git clone timed out after 30s"`) is raised
  instead. `DefaultGitRunner#timeout` exposes the configured value for introspection.
- **`git_pull_ttl` — per-pack pull freshness window** — `Config::Registry#git_pull_ttl` (default
  `86400` seconds = 24 h) controls how often `SkillSourceResolver` issues a `git pull` for an
  already-cached pack. Successive `resolve` calls within the TTL window skip the pull entirely,
  removing the previous behaviour of pulling on every resolver rebuild. Set to `0` to restore
  pull-on-every-resolve. Pull timestamps are tracked in a thread-safe, in-memory `Mutex`-guarded
  hash; they reset when the process restarts.
- **`checkout_ref` timeout** — `git checkout <ref>` is now also subject to `git_timeout`.
  A `SkillSourceResolver::ResolutionError` is raised on timeout with the ref name and pack source
  in the message.
- **`Registry::Truncatable` shared module** (`lib/rails_ai_bridge/registry/truncatable.rb`) —
  extracts the `truncate(text, max)` helper that was duplicated between `RakePresenter` and
  `RegistryCatalogFormatter`. Both classes now `include Truncatable` and the private duplicates
  are removed.
- **`Engine.to_prepare` hook** — the Rails Engine now registers a `config.to_prepare` block that
  calls `Registry.invalidate_resolver_cache!`. This discards the cached resolver on every
  Zeitwerk code reload in development, preventing stale config after an initializer change.
  In production it fires once after eager load and is effectively a no-op.
- **`depends_on` missing-dependency warning** — `PackResolver` now emits a clear `[rails-ai-bridge]`
  warning to stderr when an active pack declares `depends_on` entries that are not in the active
  pack set. The warning names each missing dependency and tells the user which manifest field to
  update. Packs still load; this is an advisory warning, not an abort. Transitive dependency
  loading remains unimplemented (see `docs/gem-general-improvements.md`).
- **Stable local pack names** — local registry packs previously received names like `local_0`,
  `local_1` based on array index, so reordering `local_registry_paths` silently shifted pack
  identities. Names are now derived from a SHA256 digest of the path
  (`local_<first 8 hex chars>`), making them stable regardless of ordering.
- **`docs/offline-mode.md`** — design plan for a future `offline:` config flag that prevents
  all git operations and serves the local cache as-is; includes rake pull task design, vendored
  snapshot pattern, and CI caching guidance.
- **`docs/gem-general-improvements.md`** — roadmap of eight broader improvements: manifest
  schema validation, pack version lock file, agent-facing JSON output from rake tasks, full
  SHA-256 cache keys, transitive `depends_on` loading, structured logging, and more.

### Changed

- **`PackResolver` errors raised as `ResolutionError`** — the two bare `raise "..."` calls in
  `PackResolver` (unknown pack name, missing tile manifest) and the one in `load_local_registries`
  now raise `SkillSourceResolver::ResolutionError` instead of a plain `RuntimeError`. Callers
  that rescue `ResolutionError` from `SkillSourceResolver` will now also catch pack-level failures
  without needing a separate `rescue RuntimeError`.
- **`SourceParser` rejects `http://` URLs** — plain HTTP was previously accepted as a git source.
  It is now rejected because cloning over unencrypted HTTP exposes credentials and pack content in
  transit. Use `https://` or `git@` (SSH) instead. The error message and module docstring are
  updated to explain the reason and list the supported formats.
- **`ListRegistry` type-guard comment** — the `unless %w[skills agents packs].include?(type)`
  guard is retained as a defence-in-depth fallback (the MCP SDK enum constraint catches invalid
  values first) and now carries an explanatory comment to prevent future confusion.
- **`Registry.build_resolver_uncached`** — wires `git_timeout` and `git_pull_ttl` from
  `Config::Registry` into `DefaultGitRunner` and `SkillSourceResolver` respectively, so
  configuration changes take effect on the next resolver rebuild.

### Fixed

- **`validate_cache_dir` documentation clarified** — the YARD docstring now explains why the
  lexical `Pathname#cleanpath` check (rather than `File.realpath`) is used: the cache directory
  may not exist yet at validation time. The security guarantee is stated explicitly: cache keys
  are SHA256-derived and not attacker-controlled, so even an unexpected symlink target is safe.

### Tests

- **`checkout_ref` — 8 new examples** covering: successful checkout returns the cache path;
  git checkout called with the correct ref; non-zero exit raises `ResolutionError`; error message
  includes ref name, source pack name, and stderr text; timeout raises `ResolutionError` with
  `"timed out"` and ref name in message; nil ref skips `git checkout` entirely.
- **Pull freshness — 3 new examples**: TTL=0 always pulls on every resolve; large TTL skips
  the second pull within the window; second resolve after TTL expiry re-pulls (verified by
  backdating `@last_pulled` via instance variable access).
- **`DefaultGitRunner` timeout — 4 new examples**: `#timeout` defaults to 30; configurable
  via constructor; clone timeout raises `RuntimeError` with duration; pull timeout same.
- **`ResolverCache` TTL spec** — replaced `sleep(0.01)` (wall-clock dependency) with an
  injectable `monotonic_clock:` lambda that returns `0` on the first call and `99_999` thereafter,
  making the TTL-expiry test deterministic and instant.
- **Total: 2043 examples, 0 failures, 94.67% line coverage** (up from 94.53%)

- **Registry data structures (PR 1)** — new `RailsAiBridge::Registry` module with immutable value objects
  porting the Rust `agent-mcp-runtime` registry types to Ruby:
  - `Registry::RegistryManifest` — root manifest (version, packs, default\_stack); `from_json` / `from_file`
  - `Registry::PackDefinition` — single pack descriptor (source, tile, always\_loaded, depends\_on)
  - `Registry::TileManifest` — pack skill/agent catalog; `from_json` / `from_file`
  - `Registry::SkillEntry`, `Registry::AgentEntry` — metadata entries for skills and agents
  - `Registry::DeprecatedEntry` — deprecation redirect (moved\_to, message, removed\_in)
  - `Registry::FrontmatterParser` — internal YAML frontmatter extractor for skill markdown files;
    used when a `SkillEntry` carries no description in `tile.json`
- **Git source resolver + pack detector (PR 2)** — git repository caching and framework auto-detection:
  - `Registry::GitRunner` — module interface for git operations (injectable for tests)
  - `Registry::DefaultGitRunner` — Open3-based implementation using stdlib git commands
  - `Registry::SkillSourceResolver` — resolves remote git sources to local cache directories;
    clones if missing, pulls if cached; cache dir defaults to `~/.rails-ai-bridge/cache/`
    (env override: `RAILS_AI_BRIDGE_CACHE_DIR`); cache key uses sanitized source + SHA256 hash
  - `Registry::DetectedFramework` — enum-like value object (Rails, Hanami)
  - `Registry::PackDetector` — detects Rails/Hanami frameworks from Gemfile content;
    supports single/double quotes, version constraints, ignores commented lines
- **Pack resolver + registry resolver (PR 3)** — priority-based pack loading and skill/agent resolution:
  - `Registry::PackResolver` — service object that resolves and loads skill packs from the registry manifest;
    handles always\_loaded packs, explicit pack selection, framework auto-detection, and local registry overrides;
    returns a `Registry::Resolver` with all packs loaded and prioritized
  - `Registry::Resolver` — core resolver that aggregates active packs and resolves queries;
    provides priority-based resolution of skills and agents, handles deprecation redirects,
    validates dependencies, and guards against path traversal attacks
  - `Registry::LoadedPack` — value object representing a loaded pack (name, tile, base\_path, priority)
  - `Registry::ResolvedSkill` — value object representing a resolved skill/agent (name, pack, path, content)
  - `Registry::SkillSummary` — value object for skill/agent catalogs (name, pack, description)
  - Priority assignment: local=0, rails/hanami=10, core=20, other=30 (lower is higher priority)
  - Path traversal guard using canonical path comparison to prevent directory escape attacks
  - Dependency validation with warnings for unsatisfied pack dependencies
- **Registry configuration (PR 4)** — configuration object for registry resolution:
  - `Config::Registry` — configuration sub-object for registry resolution settings
  - `registry.registry_manifest_path` — path to registry manifest JSON (default: `config/rails_ai_bridge_registry.json`)
  - `registry.skill_cache_dir` — directory for caching git repositories (default: `~/.rails-ai-bridge/cache`)
  - `registry.skill_packs` — explicit pack names to load, or `nil` for auto-detection based on framework
  - `registry.local_registry_paths` — local registry directory paths for skill pack overrides
  - Registry module required in main `rails_ai_bridge.rb` for configuration availability
- **Registry tools, cache, source formats, and docs (PR 5 → PR 6)** — user-visible entry points
  plus three production-quality refinements:
  - `Tools::ListRegistry` (`rails_list_registry`) — single MCP tool replacing the previous
    `rails_list_skills`, `rails_list_agents`, and `rails_list_packs`; required `type:` param
    (`"skills"` | `"agents"` | `"packs"`); optional `pack:` filter for skills/agents;
    inner `RegistryCatalogFormatter` class owns all markdown rendering (SRP)
  - `Registry::ResolverCache` — thread-safe in-memory cache for the wired `Resolver`;
    configurable TTL via `config.registry.resolver_ttl` (default 1800 s = 30 min);
    nil results never cached so manifest-missing setup retries on next call;
    `Registry.invalidate_resolver_cache!` for explicit invalidation
  - `Config::Registry#resolver_ttl` — new accessor with 1800 s default
  - `Registry::SourceParser` — new single-responsibility parser that classifies source strings
    into `:local_path`, `:git_url`, or `:github_shorthand` and resolves canonical URLs;
    raises `ResolutionError` naming all three valid formats for invalid inputs;
    `SkillSourceResolver#resolve` now delegates to `SourceParser` and returns local paths
    directly without git operations
  - `PackDefinition#ref` — new optional field for git version pinning (branch, tag, or SHA);
    `SkillSourceResolver` runs `git checkout ref` after clone/pull when set
  - `PackResolver` — default pack catalog filename changed from `tile.json` to `directory.json`;
    priority matching is now case-insensitive
  - `Registry::RakePresenter` — extracted from inline rake task logic; owns all CLI formatting
    for skill tables and resolve output
  - `rails ai:skills:list` — delegates to `RakePresenter`
  - `rails "ai:skills:resolve[pack,skill_name]"` — delegates to `RakePresenter`
  - `rails ai:skills:clear_cache` — new rake task; removes cached pack repositories and
    invalidates the in-memory resolver cache
  - `docs/skill-registry-guide.md` — new user guide covering concepts, quick start, source
    formats, priority rules, version pinning, `directory.json` format, MCP tool reference,
    rake task reference, resolver cache, troubleshooting, and security model
  - `docs/registry-resolution.md` — updated to "Registry Resolution Reference"; all
    `tile.json` references updated to `directory.json`; new source formats table; new
    `ref` field; `resolver_ttl` config option; cache management section; security section
    updated for `SourceParser`

## [3.4.0] - 2026-05-21

### Added

- **`TimedRunner` — per-introspector wall-clock timing** (#36) — new `RailsAiBridge::Introspector::TimedRunner.call(klass, app)` value object wraps any introspector class and returns `{ result:, duration_ms: }`. Uses `Process.clock_gettime(CLOCK_MONOTONIC)` for accurate measurement regardless of system clock adjustments. Duration is recorded even when the introspector raises, so you can diagnose slow-then-failing classes. Sequential runs now log duration at `debug` level via `Rails.logger.debug`.
- **Config-driven `ParallelRunner` pool size** (#36) — `config.parallel_pool_size` (default `4`) sets the upper bound for the `Concurrent::FixedThreadPool`; the actual size is `min(introspector_count, pool_size)` so no idle threads are ever created.
- **Per-future timeout for parallel introspection** (#36) — `config.parallel_timeout_seconds` (default `10`) is enforced on each `Concurrent::Future` via `future.value(timeout)`. Introspectors that exceed their budget are cancelled and return `{ error: "timed out after Ns" }` without blocking the rest of the pool. The pool's `wait_for_termination` also uses this value.
- **Rubydex incremental indexing** (#38) — new `RailsAiBridge::RubydexAdapter::IncrementalIndexer` service skips unchanged files on re-index using mtime tracking (integer seconds, no IEEE 754 precision loss). A full rebuild is triggered when the ratio of changed files exceeds `config.rubydex_incremental_threshold` (default `0.3`). The mtime snapshot can optionally survive process restarts via `config.rubydex_persist_index` (default `false`).
- **`config.rubydex_incremental_threshold`** (#38) (default `0.3`) — ratio of changed-to-total files above which the incremental indexer falls back to a full rebuild.
- **`config.rubydex_persist_index`** (#38) (default `false`) — when `true`, the rubydex mtime snapshot is written to disk alongside the index so incremental re-indexing survives process restarts.
- **Path-traversal guard for rubydex index path** (#38) — `RubydexAdapter#indexer_options` now sanitises `config.rubydex_index_path` through a `Pathname#cleanpath` + root-prefix check, returning `nil` (and falling back to the default) for any path that escapes `Rails.root`.
- **Bridge file freshness stamps** (#37) — generated bridge files (CLAUDE.md, AGENTS.md, GEMINI.md, .cursorrules, etc.) now embed a freshness header containing the generation timestamp, a 12-character source fingerprint (SHA-256 of `db/schema.rb` + `config/routes.rb`), and the gem version. Files are skipped on re-generation when their fingerprint matches, eliminating unnecessary timestamps and noisy git diffs.
- **`Fingerprinter.source_fingerprint`** (#37) — new singleton method that hashes the app's schema and routes files into a compact 12-char hex fingerprint used by the freshness system.

### Fixed (Security & Architecture Audit)

- **ReDoS Vulnerability in `RubySearch`** — Added a 2-second timeout to the `Regexp.new` engine to prevent catastrophic backtracking denial-of-service on malicious search patterns.
- **Path Traversal via Symlinks in `RubydexAdapter`** — `sanitize_index_path` now uses `Pathname#realpath` to strictly validate that the configured index path resolves safely inside the `Rails.root` boundary.
- **TOCTOU Race Condition in `IncrementalIndexer`** — Upgraded mtime tracking from integer seconds (`to_i`) to rational (`to_r`) for precise sub-second caching, preventing scenarios where high-frequency file modifications within the same second bypassed change detection.
- **Threshold Edge Case in `IncrementalIndexer`** — Changed the rebuild cutoff comparison from `>` to `>=` so that precise boundary thresholds (like 100% of files) trigger full rebuilds correctly.
- **Memory Leaks & Exhaustion in `ParallelRunner`** — Replaced deprecated `clear_active_connections!` with `connection_pool.release_connection`, and explicitly added `pool.kill` to forcefully shut down long-running threads on timeouts.
- **State Leakage in Extractors** — Refactored `FilterExtractor`, `AssociationExtractor`, and `SourceMacroExtractor` to eliminate shared mutable state, establishing purely functional object APIs and tightening private encapsulation.
- **`db/structure.sql` fallback** (#37) — `source_fingerprint` automatically falls back to `db/structure.sql` when `db/schema.rb` is absent (apps using SQL schema format are now supported).
- **`FreshnessHeader` module** (#37) — centralized utility for embedding and extracting freshness metadata from bridge files. Supports both Markdown (HTML comment header) and JSON (`_meta` object) formats, with backward-compatible parsing of older files that lack the gem-version field.
- **Bridge freshness Doctor check** (#37) — a new `BridgeFreshnessChecker` is registered with the `Doctor` service. It reports stale bridge files (fingerprint mismatch) or missing bridge files as `:warn`, and fresh files as `:pass`. The Doctor now runs 16 total checks.
- **`rails ai:check` rake task** (#37) — runs all diagnostic checks and exits with code `1` if any check fails, enabling straightforward CI/CD integration (e.g., `rails ai:check || exit 1`).
- **`CHECK=1` pre-generation guard** (#37) — pass `CHECK=1` to `rails ai:bridge` (or any bridge sub-task) to run Doctor diagnostics first; generation is aborted if any check fails.
- **`RailsAiBridge::RakeHelpers` module** (#37) — extracted top-level rake helper methods (`print_result`, `apply_context_mode_override`, `conflict_strategy`, `run_pre_generation_checks`) from global `Object` scope into a properly namespaced module.
- **`CacheWarmer` & `CachedSnapshot`** (#36) — implemented TTL-based thread-safe caching system with `config.cache_warm_on_boot` to preemptively load context into memory on application start.

### Changed

- **`rubydex` enabled by default** — The `rubydex` gem (v0.2.3) is now a mandatory dependency and semantic analysis is enabled out of the box (`@rubydex_enabled = true`). This provides zero-config code graph and semantic context functionality to all users.
- **Improved IDE configurations in documentation** — Promoted HTTP/SSE as the primary and highly recommended connection method for `rbenv`/`rvm` users within IDEs (like Antigravity and Cursor) to bypass subprocess ruby environment pathing issues.
- **`Introspector#run_single`** (#36) — sequential execution is now routed through `TimedRunner` instead of a bare `rescue` block. Error handling behaviour is unchanged (`{ error: message }`), but every introspector call now produces a debug-level duration log entry.
- **`ParallelRunner#resolve_future`** (#36) — uses `future.value(timeout)` + `future.complete?` check instead of blocking `future.value!`. A `nil` return from a timed-out future is no longer misinterpreted as a successful result.
- **`ParallelRunner` pool shutdown** (#36) — `wait_for_termination` now uses `config.parallel_timeout_seconds` instead of a hardcoded `10`.
- **`RubydexAdapter#handle_index_result`** (#38) — on `:reindex!` failure, existing `@graph` and `@indexed` state is preserved rather than reset to `nil`/`false`, preventing a full context blackout on transient indexing errors.
- **Integer mtimes throughout `IncrementalIndexer`** (#38) — `serialize_mtimes`, `deserialize_mtimes`, and `file_mtime` now all operate in integer seconds (`Time#to_i`) to avoid IEEE 754 floating-point comparison drift.
- **`FreshnessHeader`** (#37) — expanded API with `embed_for(fmt, ...)`, `extract_metadata_for(fmt, content)`, and `extract_fingerprint_for(fmt, content)` dispatching methods. JSON and Markdown branching is now fully centralized here, removing format-aware `if fmt == :json` conditionals from callers.
- **`ContextFileSerializer`** (#37) — refactored to use a new `FreshnessWriter` inner class that encapsulates freshness metadata embedding and file write decisions. This eliminates `ControlParameter`, `UtilityFunction`, and `LongParameterList` Reek warnings.
- **`BridgeFreshnessChecker`** (#37) — refactored with a `ScanResult` struct to eliminate the 6-parameter `check_file` method; introduced `scan_files`, `accumulate_file_result`, `stale?`, and `freshness_check` helpers reducing `TooManyStatements` and `DuplicateMethodCall` Reek warnings.
- **`Fingerprinter.source_fingerprint`** (#37) — extracted `schema_path(root)` and `read_source_content(paths)` private helpers to reduce method statement count.
- **`RubySearch`** (#35) — wrapped the 5 search params into a `SearchParams` struct to resolve the `TooManyInstanceVariables` Reek warning; extracted `secret_file?(basename)` from `skip_file?` to fix `FeatureEnvy`; added `SECRET_EXTENSIONS` constant.
- **`RipgrepSearch::CommandBuilder`** (#35) — moved hardcoded secret file globs to a `SECRET_EXCLUDES` constant; renamed helpers to `excluded_path_flags` / `secret_exclude_flags`; added `# :reek:UtilityFunction` suppressions for intentional stateless helpers.
- **`Validator`** (#35) — extracted `effective_max_bytes`, `present?`, `normalize_extension`, `safe_extension?`, `build_search_path`, `within_root?`, `path_not_found`, and `pattern_too_long_error` helpers. Fixes `DuplicateMethodCall` on `BaseTool.text_response("Path not found: ...")` in `validate_path_security`.
- **`SourceMacroExtractor`** (#35) — split `add_attachment_macros` into three single-step helpers (`add_single_attached`, `add_many_attached`, `add_rich_text`) to reduce statement counts.
- **Rake namespace splitting** (#35) — `namespace :ai` reopened across multiple smaller blocks in `rails_ai_bridge.rake` to comply with `Metrics/BlockLength` RuboCop limit.

### Fixed

- **`ASSISTANT_TABLE` constant redefinition warning** (#35) — wrapped constant definition in `unless defined?` to prevent warnings when Rake tasks are loaded multiple times in test environments.

### Tests

- Added **68 new examples** covering:
  - `TimedRunner` — result forwarding, error capture, monotonic duration, error-path duration
  - `ParallelRunner` — config-driven pool size, per-future timeout, pool shutdown, mixed success/failure, `available?` with pool-size and missing-constant edge cases
  - `Introspector` — sequential `TimedRunner` wiring (plain result, no `duration_ms` envelope), error capture in sequential mode, debug log assertion
  - `AppOverviewFormatter` — nil/error guards, optional fields, field ordering
  - `GemsFormatter` — nil/error guards, total count, Notable Gems section, category+name sort order
  - `MigrationsFormatter` — nil/error guards, schema version, pending migrations count, recent migrations with and without actions
  - `RubySearch` / `FileProcessor` — pattern matching, max_results cap, secret file skipping (`.env`, `.key`, `.pem`, `.p12`, `.pfx`, `.crt`), excluded paths, file_type filtering, case-insensitive search, relative paths, unreadable file recovery, `:full` return signal
  - `Fingerprinter` — restored `.compute` and `.changed?` unit tests; added `db/structure.sql` fallback and schema.rb-wins-when-both-exist edge cases
  - `FreshnessHeader` — backward-compatible parsing of headers without gem version
- **Total: 1,745 examples, 0 failures, 94.49% line coverage** (up from 94.04%)

## [3.2.0] - 2026-05-04

### Added

- **Recursive symlink protection** — `FileManagementService` now recursively resolves and validates every directory component of a path. This prevents directory-traversal escapes via symlinks in non-existent nested paths (e.g., writing to `unsafe_link/new_dir/file.txt`).
- **ActiveRecord-free resilience** — `NonArModelsIntrospector` now safely handles Rails stacks without ActiveRecord (e.g., pure API or alternative ORMs) by guarding `ActiveRecord::Base` inheritance checks.
- **Robust Rails logger guards** — all diagnostic and error logging now uses `defined?(Rails.logger)` to prevent `NoMethodError` in environments where `Rails` is defined but lacks a logger.

### Changed

- **Terminology alignment** — Updated generated documentation and command descriptions from "context" to "bridge" (e.g., `rails ai:watch` now describes "Auto-regenerate bridge files").
- **ConventionDetector stability** —restored standard error-hash return `{ error: msg }` for `ConventionDetector#call` to comply with introspector standards, while maintaining explicit `Rails.logger.warn` for observability.

### Fixed

- **Rake task spec cleanup** — removed unused `let(:task_path)` and fixed duplication in rake task loading.
- **Install generator optimization** — removed redundant double-introspection call during the install process.
## [3.1.1] - 2026-05-03

### Changed

- **Small Security Improvement** — There was an update from rubygems security, so this made
  a new release needed, no new functionality added

## [3.1.0] - 2026-05-01

### Added

- **Task-relevance ordering for compact context** — model lists now rank by semantic tier,
  structural complexity, route density, recent migrations, and optional database-size signals
  instead of relying mostly on alphabetical order.
- **Endpoint focus summaries** — compact stack/project context now surfaces the busiest route
  targets with direct `rails_get_routes(controller:"...", detail:"summary")` drill-down hints.
- **Database size buckets** — the optional `database_stats` introspector now annotates PostgreSQL
  approximate row counts as `small`, `medium`, `large`, or `hot`; generated context shows these
  hints only when `database_stats` is explicitly enabled.
- **Context quality matrix specs** — generated-output acceptance coverage now exercises standard
  CRUD, large-schema, API-only, Hotwire, engine-style, and regulated/no-domain-metadata profiles,
  with real Rails-shaped fixture trees for API-only, Hotwire, large-schema, engine-style, and
  regulated/no-domain-metadata apps plus bounded output and secret-adjacent regression checks.
- **Serialization benchmark guard** — large-fixture compact serialization now has a small
  performance budget to catch accidental context bloat.
- **MCP large-payload stability checks** — route/schema tool specs now exercise truncation,
  pagination, next-offset guidance, and section-cache reuse against large payloads.

### Changed

- **Claude rules** — `.claude/rules/rails-context.md` now includes bounded endpoint focus and
  route drill-down guidance; `.claude/rules/rails-schema.md` adds optional size-bucket hints.
- **Route MCP pagination** — `rails_get_routes` standard/full output now includes a next
  `offset` hint when more route rows are available.
- **Secret-bearing config paths** — generated context, `rails_get_conventions`, and the
  `rails://conventions` MCP resource now omit dotenv files, Rails credentials files, secret/private
  directories, master keys, and private key material from config-file listings while preserving
  safe operational files such as `config/database.yml`.
- **Convention detection with custom Rails paths** — architecture and directory-structure signals
  now honor configured Rails paths for directories such as `app/models` and `app/services` while
  keeping generated output on logical names instead of absolute local paths.
- **Model introspection with custom Rails paths** — ActiveRecord source-derived metadata and
  `non_ar_models` discovery now resolve every configured `app/models` path, so apps that place
  domain models outside the conventional directory still generate useful model context.
- **Controller and frontend introspection with custom Rails paths** — controller source metadata,
  view summaries, Stimulus controllers, and Turbo frame/stream/broadcast detection now honor
  configured `app/controllers`, `app/views`, `app/helpers`, `app/components`, and
  `app/javascript/controllers` paths where Rails exposes them.
- **View detail access with custom Rails paths** — `rails_get_view(path:"...")` and
  `rails://views/{path}` now resolve files through configured `app/views` paths while preserving
  traversal protection.
- **Specialized introspectors with custom Rails paths** — Active Storage, Action Text,
  CurrentAttributes, API serializers/GraphQL/versioning/rate-limit scans, Devise,
  `has_secure_password`, Rails auth, Pundit, and CanCanCan detection now honor configured logical
  Rails paths instead of assuming only conventional `app/*` directories.
- **Copilot, Codex, Cursor, Windsurf, and shared compact serializers** — key model sections now
  use the same relevance score so assistants see core, routed, recently changed, or hot-domain
  models before lower-signal supporting models.
- **Generated override guidance** — compact instructions no longer include the literal
  omit-merge marker string unless reading the actual override stub; user-facing docs still explain
  how to activate `config/rails_ai_bridge/overrides.md`.

## [3.0.0] - 2026-04-28

### Added

- **Interactive install generator** — `rails generate rails_ai_bridge:install` now prompts for an
  install profile: `custom` (per-format prompts), `minimal` (thin shims, no split-rule dirs),
  `full` (all formats + split-rule dirs), or `mcp` (only `.mcp.json`, generate files later).
  Pass `--profile=<name>` to skip the prompt, or `--skip-context` to defer all file generation
  (useful in CI/CD pipelines).
- **`split_rules:` parameter on `generate_context`** — `RailsAiBridge.generate_context` and
  `ContextFileSerializer` now accept `split_rules: false` to skip generating per-assistant
  rule directories (`.claude/rules/`, `.cursor/rules/`, etc.). Used by the `minimal` profile
  to avoid creating directories that aren't needed for simple shim installs.
- **`on_conflict:` option on `generate_context` and `ContextFileSerializer`** — controls what
  happens when a generated file already exists with different content.
  - `:overwrite` (default) — silently replaces the file (no behaviour change for existing users)
  - `:skip` — keeps the existing file unchanged
  - `:prompt` — asks interactively via stdin before overwriting
  - `Proc` — caller supplies `(filepath) -> bool`; return `true` to overwrite
  Rake tasks expose this via `CONFIRM=1 rails ai:bridge` (enables `:prompt` for all bridge tasks).
- **`config.watcher_formats`** — limits which formats `rails ai:watch` regenerates on file change.
  Defaults to `:all`. Set to e.g. `%i[claude cursor]` to avoid regenerating formats you don't use
  during active development.

### Changed

- **`RailsAiBridge.generate_context` signature** — keyword parameters (`format:`, `split_rules:`,
  `on_conflict:`) are now forwarded via `**options` (two formal parameters instead of four).
  All existing call sites using keyword arguments are unaffected.
- **`Providers::Factory` strategy pattern** — `ContextFileSerializer` now dispatches serializers
  and split-rule generators through a registry factory (`REGISTRY` + `SPLIT_REGISTRY`) instead
  of hardcoded `case`/`if` chains, making it trivial to add new output formats.
- **`ProfileResolver` extraction** — install profile resolution logic extracted from
  `InstallGenerator` into a dedicated `Generators::InstallGenerator::ProfileResolver` class,
  with Thor shell injected via `shell:` so existing tests remain intact.
- **`GemRegistry` extraction** — `NOTABLE_GEMS` constant and categorization logic extracted from
  `GemIntrospector` into `Introspectors::GemRegistry`, eliminating a duplicate `detect_notable_gems`
  call in the introspection pipeline.

### Removed

- **`exe/rails-ai-bridge` standalone CLI** — the `rails-ai-bridge serve / bridge / inspect`
  binary has been removed. All commands are available as rake tasks (`rails ai:serve`,
  `rails ai:bridge`, `rails ai:inspect`, etc.) which are the recommended interface.

---

## [2.2.0] - 2026-04-04

### Added

- **`non_ar_models` introspector** — Lists Ruby classes under `app/models` that are not
  ActiveRecord models, tagged **`[POJO/Service]`** in MCP listings and
  `.claude/rules/rails-models.md`. Context key: `:non_ar_models` with
  `{ non_ar_models: [{ name, relative_path, tag }] }`. **Not** in `:standard` or
  `:full` presets (opt in via `config.introspectors << :non_ar_models`).
  Included in the `domain_metadata` disable category when enabled.
- **Model semantic classification** — Each ActiveRecord model in introspection
  output now includes `semantic_tier` (`core_entity`, `pure_join`, `rich_join`,
  `supporting`) and `semantic_tier_reason` for MCP transparency. Join tables
  used in `has_many :through` are detected; payload columns beyond FKs and
  metadata yield `rich_join`.
- **`config.core_models`** — List model class names to tag as `core_entity` for
  AI-focused context (initializer comment + `Config::Introspection`).
- **`RailsAiBridge::ModelSemanticClassifier`** — PORO that computes tiers from
  columns, `belongs_to` foreign keys, and through-association membership.
- **`.claude/rules/rails-context.md`** — Semantic layer summary (app metadata +
  models grouped by tier) for Claude Code, alongside existing split rules.

### Changed

- **`rails-context.md` tier lists** — In compact `context_mode`, at most 20 model names
  per `semantic_tier` with an overflow line referencing
  `rails_get_model_details(detail:"summary")`; full mode lists all names per tier.
- **Claude rules `rails-models.md`** — Each model line includes `tier: …` when present.
- **`rails_get_model_details` formatters** — Summary, standard, full, and
  single-model views include semantic tier where applicable.
- **Combustion test setup** — `Combustion.path` is set to `spec/internal`,
  `Combustion::Database.setup` runs after boot so `:memory:` SQLite has schema
  before examples, and the internal `ExampleJob` no longer subclasses
  `ActiveJob::Base` (Active Job is not loaded in the minimal stack).

## [2.1.0] - 2026-04-02

### Added

- **Gemini Support:** Added support for Google's Gemini AI assistant via `GEMINI.md`.
- **New Rake Task:** Added `rails ai:bridge:gemini` to generate Gemini-specific context.
- **Context Harmonization:** Refactored all provider serializers (Claude, Gemini, Codex,
  Copilot, Cursor, Windsurf) to use a shared `BaseProviderSerializer`.
- **Enhanced AI Guidance:** All context files now feature directive headers,
  complexity-sorted model lists, and explicit behavioral rules to improve AI
  code generation.
- **Improved Metadata:** Context files now include descriptions for key config
  files and standard maintenance commands (e.g., `rubocop`).

### Changed

- **Internal Refactor:** Extracted common rendering logic into
  `RailsAiBridge::Serializers::Providers::BaseProviderSerializer` to ensure
  consistency and maintainability across all AI assistants.

## [2.0.0] - 2026-03-31

### Added

- **Shared runtime context provider** — MCP tools and `rails://...` resources now read through
  `RailsAiBridge::ContextProvider`, keeping cache invalidation and snapshot semantics
  aligned across both entry points.
- **Explicit extension registries** — `config.additional_introspectors`, `config.additional_tools`,
  and `config.additional_resources` allow host apps or companion gems to extend the built-ins
  without patching core constants.
- **HTTP transport Rack builder** — `RailsAiBridge::HttpTransportApp` centralizes HTTP MCP request
  handling for both standalone server mode and middleware auto-mount.
- **Section-level context reads** — `ContextProvider.fetch_section` and `BaseTool.cached_section`
  let single-section tools avoid rebuilding or materializing the full snapshot path
  when unnecessary.
- **Folder-level contributor docs** — key runtime folders now include local `README.md` guides
  for structure, boundaries, and extension points.
- **Extensibility integration coverage** — specs now prove that a custom introspector, tool,
  and resource can be registered and used together from the host app configuration surface.
- **Serializer formatter objects** — `MarkdownSerializer` is now a thin orchestrator delegating to
  37 single-responsibility `Formatters::*` classes; each formatter is independently testable
  and injectable.
- **Tool response formatters** — `GetSchema` and `GetModelDetails` delegate all rendering to
  `Tools::Schema::*` and `Tools::ModelDetails::*` formatter classes; tool `call` methods
  are ≤20 lines each.
- **`Config::Auth`, `Config::Server`, `Config::Introspection`, `Config::Output`** — `Configuration`
  is now a `Forwardable` facade over four focused sub-objects; each is independently readable
  and injectable.
- **`Mcp::Authenticator`** — consolidates strategy resolution, static-token lookup, and
  configuration predicates into a single entry point, replacing the previous split between
  `McpHttpAuth` and `Mcp::HttpAuth`.
- **`Mcp::HttpRateLimiter`** — optional in-process sliding-window rate limiter per client IP;
  configured via `config.mcp.rate_limit_max_requests` and `config.mcp.rate_limit_window_seconds`.
  Returns 429 with `Retry-After` header when exceeded.
- **`Mcp::HttpStructuredLog`** — optional one-JSON-line-per-request logger for the MCP HTTP path;
  enabled via `config.mcp.http_log_json = true`. Logs `event`, `http_status`, `path`,
  `client_ip`, and `request_id`; never logs tokens or full Rack env.
- **`Config::Mcp`** — new `config.mcp` sub-object (5th façade sub-config) for MCP HTTP operational
  settings: `mode`, `security_profile`, `rate_limit_max_requests`, `rate_limit_window_seconds`,
  `http_log_json`, `authorize`, `require_auth_in_production`.
- **`config.mcp.authorize`** — optional post-auth lambda `(context, request) { truthy }`; returning falsey yields HTTP 403 on the MCP path.
- **`config.mcp.require_auth_in_production`** — when `true`, boot fails in production unless an auth mechanism is configured.
- **`HttpTransportApp`** updated — request pipeline is now: path check → auth → authorize → rate limit → structured log → transport.
- **`SectionFormatter` template method base** — 22 of 37 formatters now inherit from `SectionFormatter`,
  which handles the nil/error guard in one place; each formatter only implements `render(data)`.
- **`Serializers::Providers` namespace** — 10 LLM provider serializers extracted into
  `lib/rails_ai_bridge/serializers/providers/`, separating provider concerns from domain
  infrastructure (`MarkdownSerializer`, `JsonSerializer`, formatters).
- **`UPGRADING.md`** — new upgrade guide documenting `config.mcp` settings, rate limit semantics, structured logging, `authorize` behaviour, and the `require_auth_in_production` flag.
- **Contributor roadmaps** — `docs/roadmaps.md`, `docs/roadmap-mcp-v2.md`, `docs/roadmap-context-assistants.md` added.

### Changed

- **Install generator messages** — the install flow now reports created vs unchanged files correctly
  and the generated initializer comments reflect the current preset sizes.
- **Fingerprint reuse on invalidation** — context refresh reuses a single fingerprint snapshot per
  fetch cycle instead of scanning twice when cached context becomes stale.
- **`FullClaudeSerializer`, `FullRulesSerializer`, `FullCopilotSerializer`, `FullCodexSerializer`
  removed** — full-mode rendering is now handled by injecting header/footer formatter classes into
  `MarkdownSerializer` via constructor arguments; no subclassing needed.
- **Test suite expanded to 841 examples at ≥87% line coverage.**

### Fixed

- **Install generator output bug** — `generate_context` results are no longer iterated as raw hash pairs
  during install-time file generation.
- **`StandardFormatter` pagination hint** — navigation hint now correctly uses `offset + limit < total`
  (consistent with `SummaryFormatter` and `FullFormatter`), preventing a spurious hint
  on the last page.

### Upgrading from 1.x

**No configuration changes required.** Every `config.*` attribute from 1.x is still available unchanged —
  `Configuration` now delegates to focused sub-objects (`Config::Auth`, `Config::Server`,
  `Config::Introspection`, `Config::Output`, `Config::Mcp`) but exposes the same flat DSL.

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
