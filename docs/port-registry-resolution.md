# Port Registry Resolution from Rust Runtime to rails-ai-bridge

**Status:** Complete — PR 1 ✅, PR 2 ✅, PR 3 ✅, PR 4 ✅, PR 5 ✅
**Reference source:** `../agent-mcp-runtime/src/registry/` (Rust)
**Delivery model:** Sequential PRs, each reviewed by Qodo + CodeRabbit before proceeding

## Objective

Port the registry resolution logic from `agent-mcp-runtime` (Rust) into `rails-ai-bridge` (Ruby). This enables the bridge
to resolve skill packs from git repositories, handle priority-based loading, and support deprecation redirects —
necessary for the future skill compiler feature.

## Agreed Decisions (pre-implementation)

| Topic | Decision |
|---|---|
| Long-term home | Yes — `rails-ai-bridge` is the canonical location (production gem, 2k+ downloads) |
| `ContextProviderDefinition` / `ContextToolSpec` | **Deferred** (YAGNI — not in registry.json, no integration milestone) |
| Git operations | Use `Open3` (stdlib) — no new gem dependency |
| `ruby-skill-bench` `PackResolver` | Stays independent — no cross-repo dependency |
| MCP tools | `rails_list_registry` (unified — replaces the originally-planned split `rails_list_skills` / `rails_list_agents` / `rails_list_packs` tools); `rails_use_skill` / `rails_use_agent` **deferred** |
| Configuration access | New `Config::Registry` sub-object; accessed as `configuration.registry.*` — no top-level delegators |
| Priorities | Hardcoded matching Rust (`local=0`, `rails/hanami=10`, `core=20`, `other=30`) |
| Frontmatter parser | Include as internal utility (`Registry::FrontmatterParser`) — used when `tile.json` `SkillEntry` has no `description` |

## PR 1 — Completed ✅

**Implemented:** Data structures + frontmatter parser

**Files created:**
- `lib/rails_ai_bridge/registry/registry_manifest.rb` — `RegistryManifest` (Zeitwerk-compliant)
- `lib/rails_ai_bridge/registry/pack_definition.rb` — `PackDefinition` (Zeitwerk-compliant)
- `lib/rails_ai_bridge/registry/tile_manifest.rb` — `TileManifest`, `SkillEntry`, `AgentEntry`, `DeprecatedEntry`
- `lib/rails_ai_bridge/registry/frontmatter_parser.rb` — `FrontmatterParser`, `SkillMetadata`, `ParseError`
- `lib/rails_ai_bridge/registry.rb` — module entry point
- `spec/lib/rails_ai_bridge/registry/registry_manifest_spec.rb` — 14 examples
- `spec/lib/rails_ai_bridge/registry/pack_definition_spec.rb` — 2 examples
- `spec/lib/rails_ai_bridge/registry/tile_manifest_spec.rb` — 29 examples
- `spec/lib/rails_ai_bridge/registry/frontmatter_parser_spec.rb` — 9 examples

**Decisions made during implementation:**
- **Zeitwerk naming**: Split `manifest.rb` into `registry_manifest.rb` + `pack_definition.rb` so filenames map to constants. No `require_relative` calls needed in `registry.rb` — Zeitwerk autoloads everything correctly.
- **Error handling**: `parse_yaml` now guards `Psych::SyntaxError` (invalid YAML) and non-Hash YAML (sequences/scalars), raising `ParseError` consistently in both cases.
- **Reek suppressions**: Added `NilCheck` suppression for `DeprecatedEntry#removed_in?` (intentional nil check on value object predicate) and `TooManyStatements` for `FrontmatterParser#extract_frontmatter_lines` (necessary complexity for delimiter scanning).
- **Spec coverage**: 52 examples covering happy paths, defaults, file errors, invalid YAML, non-mapping YAML, and edge cases.

**Quality gates:** 52/52 specs green · rubocop clean · reek 0 warnings · coverage 81.36%

## PR Breakdown

### PR 1 — Data structures + frontmatter parser

**Files:**
- `lib/rails_ai_bridge/registry/registry_manifest.rb` — `RegistryManifest`
- `lib/rails_ai_bridge/registry/pack_definition.rb` — `PackDefinition`
- `lib/rails_ai_bridge/registry/tile_manifest.rb` — `TileManifest`, `SkillEntry`, `AgentEntry`, `DeprecatedEntry`
- `lib/rails_ai_bridge/registry/frontmatter_parser.rb` — YAML frontmatter extraction (internal utility)
- `lib/rails_ai_bridge/registry.rb` — module entry point
- `spec/lib/rails_ai_bridge/registry/registry_manifest_spec.rb`
- `spec/lib/rails_ai_bridge/registry/pack_definition_spec.rb`
- `spec/lib/rails_ai_bridge/registry/tile_manifest_spec.rb`
- `spec/lib/rails_ai_bridge/registry/frontmatter_parser_spec.rb`

**Notes:**
- `RegistryManifest` omits `context_providers` (deferred)
- `json` gem is standard library in Ruby 3+ — no gemspec change needed
- Port test cases from `manifest.rs`, `tile.rs`, and `parser.rs` Rust tests

### PR 2 — Git source resolver + pack detector ✅

**Implemented:** Git repository caching and framework auto-detection

**Files created:**
- `lib/rails_ai_bridge/registry/skill_source_resolver.rb` — `GitRunner` interface, `DefaultGitRunner` (Open3), `SkillSourceResolver` with cache management
- `lib/rails_ai_bridge/registry/pack_detector.rb` — `DetectedFramework` enum, `PackDetector` for Gemfile parsing
- `spec/lib/rails_ai_bridge/registry/skill_source_resolver_spec.rb` — 23 examples
- `spec/lib/rails_ai_bridge/registry/pack_detector_spec.rb` — 18 examples

**Decisions made during implementation:**
- **Zeitwerk naming**: File renamed from `git_source_resolver.rb` to `skill_source_resolver.rb` to match constant name `SkillSourceResolver`.
- **Path validation**: Added `validate_cache_dir` using `Pathname#cleanpath` to prevent path traversal attacks on cache directory.
- **Source format validation**: Added `validate_source_format` with regex to validate `owner/repo` format before git operations, providing early error detection.
- **Security**: Open3 array arguments prevent shell injection; cache key sanitization prevents filesystem issues.
- **Error handling**: Custom `ResolutionError` wraps git operation failures with context (source + original error).
- **Resource cleanup**: Specs use `begin...ensure` blocks to guarantee temp directory cleanup even on test failures.
- **Documentation**: Updated YARD @see in `registry.rb` to remove explicit file path, matching other references.
- **Reek suppressions**: Added justified suppression for `resolve` method (necessary complexity for validation, cache lookup, and git operations).

**Quality gates:** 117/117 specs green · rubocop clean · reek 0 warnings · skunk score 2.19 · coverage 85.42%

### PR 3 — Pack resolver + registry resolver ✅

**Implemented:** Priority-based pack loading and skill/agent resolution

**Files created:**
- `lib/rails_ai_bridge/registry/pack_resolver.rb` — `PackResolver` with priority-based loading,
  auto-detect or explicit packs, local registry support
- `lib/rails_ai_bridge/registry/resolver.rb` — `Resolver` with `LoadedPack`, `ResolvedSkill`,
  `SkillSummary`; `resolve_skill`, `resolve_agent`, `list_skills`, `list_agents`, `validate_dependencies`,
  `check_deprecated`, `active_packs`
- `spec/lib/rails_ai_bridge/registry/pack_resolver_spec.rb` — 23 examples
- `spec/lib/rails_ai_bridge/registry/resolver_spec.rb` — 31 examples

**Decisions made during implementation:**
- **Zeitwerk naming**: Class named `PackResolver` (not `PackResolverService`) to match filename.
- **Constants**: Added pack name constants (`RAILS_PACK`, `HANAMI_PACK`, `CORE_PACK`) and priority constants
  (`PRIORITY_HIGH`, `PRIORITY_MEDIUM`, `PRIORITY_LOW`) for single source of truth.
- **Dependency injection**: `PackResolver#initialize` accepts optional `pack_detector` for testability.
- **Path traversal guard**: Updated `descendant?` to enforce path-separator boundary after canonicalization
  to prevent false positives from sibling directories. Narrowed rescue to specific filesystem errors.
- **Security**: Path traversal guard uses `Pathname#realpath` to resolve symlinks before comparison.
- **Error handling**: Tile manifest read errors and JSON parse errors raise descriptive exceptions.
- **Spec coverage**: 54 examples covering happy paths, priority ordering, deprecation redirects,
  dependency validation, local registries, error cases, and path traversal attacks.

**Quality gates:** 161/161 specs green · rubocop clean · reek 33 warnings (acceptable) · skunk 27.3 (acceptable) · coverage 88.85%

### PR 4 — Configuration + integration

**Files:**
- `lib/rails_ai_bridge/config/registry.rb` — `Config::Registry` sub-object
  - `registry_manifest_path` (default: `config/rails_ai_bridge/registry.json`)
  - `skill_cache_dir` (default: `~/.rails-ai-bridge/cache`)
  - `skill_packs` (default: `nil` — triggers auto-detection)
  - `local_registry_paths` (default: `[]`)
- Wire `Config::Registry` into `Configuration#initialize` as `@registry`; expose via `attr_reader :registry`
- Update `lib/rails_ai_bridge.rb` — require registry module
- `spec/lib/rails_ai_bridge/config/registry_spec.rb`

### PR 5 — Rake tasks + MCP tools + documentation

**Files:**
- Append to `lib/rails_ai_bridge/tasks/rails_ai_bridge.rake`:
  - `rails_ai_bridge:list_skills` — prints skill catalog from registry
  - `rails_ai_bridge:resolve_skill[pack,name]` — resolves and prints skill content
- `lib/rails_ai_bridge/tools/list_registry.rb` — unified `rails_list_registry` tool (replaces
  the originally-planned split `rails_list_skills`, `rails_list_agents`, `rails_list_packs`)
- `spec/lib/rails_ai_bridge/tools/list_registry_spec.rb`
- `docs/registry-resolution.md` — user-facing docs (consolidated into this file afterwards; see "Registry Resolution Reference")

## Deferred (follow-up)

- `rails_use_skill` / `rails_use_agent` MCP tools — needs clearer UX rationale for in-app context
- `ContextProviderDefinition` / `ContextToolSpec` — no integration milestone yet

## Methodology

- TDD — write failing specs before implementation on each PR
- Port Rust test cases as the baseline; add Ruby-specific edge cases on top
- Target >90% test coverage (consistent with current gem standard)
- Run `rubocop`, `reek`, and `skunk` before each PR; resolve all offenses
- YARD docs on all public methods and classes
- Principles: DRY, Service Objects, KISS, CoC, YAGNI
- No cross-repo dependencies (especially `ruby-skill-bench` stays independent)
- Every PR updates `CHANGELOG.md` (Unreleased section) with what was added/changed
- `README.md` updated in the PR where the feature becomes user-visible (PR 4 for config, PR 5 for Rake tasks and MCP tools)
- `UPGRADING.md` updated if any breaking change or new required config is introduced

## Success Criteria

- [x] All registry modules created with passing specs (PR 1–3)
- [x] `Config::Registry` wired and documented (PR 4)
- [x] `rails ai:skills:list` and `rails "ai:skills:resolve[pack,name]"` Rake tasks work (PR 5)
- [x] `rails_list_registry` MCP tool exposed (PR 5 — unified, replaces split tools)
- [x] `docs/registry-resolution.md` written (PR 5; later consolidated into this file)
- [x] Priority-based resolution handles core/rails/hanami/planning correctly
- [x] Deprecation redirects work (old skill name → new location)
- [x] Path traversal guard enforced in resolver
- [x] `CHANGELOG.md` updated in every PR
- [x] `README.md` updated in PR 4 and PR 5
- [ ] `UPGRADING.md` updated if breaking changes are introduced (no breaking changes introduced)
- [ ] All PRs pass Qodo + CodeRabbit review gates

## Naming deltas from the original plan

The original plan (formerly `docs/02-port-registry-resolution.md`) proposed names that changed
during implementation:

- Rake tasks shipped as `ai:skills:list` / `ai:skills:resolve[pack,name]` (planned:
  `ai:list_skills` / `ai:resolve_skill`).
- Configuration lives under `config.registry.*` (`Config::Registry` sub-object).
- The MCP surface is the unified `rails_list_registry` tool plus `rails_resolve_skill`; the
  split `rails_list_skills` / `rails_list_agents` / `rails_list_packs` tools were never built.
- Git operations use `Open3` (stdlib) — no `git` gem dependency.

---

## Registry Resolution Reference

> This section consolidates the former `docs/registry-resolution.md` user-facing reference.
> That file (and the original `docs/02-port-registry-resolution.md` plan) were removed in the
> docs cleanup; this is now the single canonical document for the registry port and its
> user-facing behavior. For concepts and step-by-step setup, see the
> [Skill Registry Guide](skill-registry-guide.md).

rails-ai-bridge can load **skill packs** — curated collections of agent skills and workflows —
from versioned git repositories and make them discoverable via MCP tools and rake tasks.

### What a skill pack is

A skill pack is a git repository that contains:

- A **`directory.json`** manifest listing available skills and agents
- Markdown skill files (e.g. `skills/code-review.md`) referenced by the manifest
- Optional deprecation redirects when skills are renamed

When a pack is loaded, its skills and agents appear in `rails_list_registry`, and any skill can be
resolved to full content for an AI client.

### Quick start

**1. Create the registry manifest** at `config/rails_ai_bridge/registry.json`:

```json
{
  "version": "1.0.0",
  "packs": {
    "rails": {
      "source": "igmarin/rails-agent-skills",
      "always_loaded": false
    },
    "core": {
      "source": "igmarin/ruby-core-skills",
      "always_loaded": true
    }
  },
  "default_stack": ["core"]
}
```

**2. Configure the bridge** in `config/initializers/rails_ai_bridge.rb`:

```ruby
RailsAiBridge.configure do |config|
  config.registry.registry_manifest_path = "config/rails_ai_bridge/registry.json"
end
```

**3. Verify** packs are loaded:

```bash
rails ai:skills:list
```

### Registry manifest format

| Field | Type | Description |
|-------|------|-------------|
| `version` | String | Manifest schema version (currently `"1.0.0"`) |
| `packs` | Object | Map of pack name → pack definition |
| `default_stack` | Array | Pack names loaded when no framework is detected |

#### Pack definition fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `source` | String | Yes | — | Pack source: local path, full git URL, or `owner/repo` GitHub shorthand |
| `tile` | String | No | `"directory.json"` | Relative path to the pack's catalog file |
| `always_loaded` | Boolean | No | `false` | Load this pack regardless of framework detection |
| `depends_on` | Array | No | `[]` | Other pack names this pack requires |
| `ref` | String | No | `nil` | Git branch, tag, or SHA to check out; `nil` uses the default branch |

#### Source formats

The `source` field accepts a local path, an HTTPS/SSH git URL, or a GitHub `owner/repo` shorthand:

| Format | Example |
|--------|---------|
| Local path | `/abs/path`, `./relative`, `../sibling` |
| HTTPS URL | `https://github.com/org/repo.git` |
| SSH URL | `git@github.com:org/repo.git` |
| GitHub shorthand | `owner/repo` (expanded to `https://github.com/owner/repo.git`) |

> **Note:** plain `http://` URLs are rejected to prevent unencrypted transmission of credentials
> and pack content. Use `https://` or `git@` (SSH) instead.

### Priority rules

Packs are assigned priorities based on their name (case-insensitive exact match). Lower number = higher priority.

| Pack name | Priority | Reasoning |
|-----------|----------|-----------|
| `local_*` (local registries) | 0 | Highest — local overrides always win |
| `rails`, `hanami` | 10 | Framework-specific packs shadow generic ones |
| `core` | 20 | Core packs provide defaults |
| Any other name | 30 | Lowest — third-party or custom packs |

When the same skill name appears in multiple packs, the version from the **highest priority** pack (lowest number) is returned.

Note: only exact name matches qualify for high/medium priority. `rails-extras` gets priority 30.

### Configuration options

All options live under `config.registry.*`:

| Option | Default | Description |
|--------|---------|-------------|
| `registry_manifest_path` | `"config/rails_ai_bridge/registry.json"` | Path to the registry manifest JSON |
| `skill_cache_dir` | `~/.rails-ai-bridge/cache` | Directory for caching cloned git repositories |
| `skill_packs` | `nil` | Explicit list of pack names to load, or `nil` for auto-detection |
| `local_registry_paths` | `[]` | Local directory paths containing a `directory.json` (loaded at priority 0) |
| `resolver_ttl` | `1800` | Seconds to keep the wired `Resolver` in memory before rebuilding (default: 30 min) |
| `git_pull_ttl` | `86400` | Seconds between `git pull` refreshes per cached pack (default: 24 h). Set to `0` to pull on every resolver rebuild |
| `git_timeout` | `30` | Seconds before a git operation (clone, pull, checkout) is forcibly interrupted and a `ResolutionError` raised |

#### Auto-detection

When `skill_packs` is `nil`, the bridge auto-detects the framework from your `Gemfile`:

- Rails detected → loads the `rails` pack
- Hanami detected → loads the `hanami` pack
- Neither detected → falls back to `default_stack` from the manifest

Set `skill_packs` explicitly to bypass auto-detection:

```ruby
config.registry.skill_packs = %w[rails core]
```

#### Local registry paths

Use `local_registry_paths` to load packs from local directories (useful during pack development):

```ruby
config.registry.local_registry_paths = ["/path/to/my-local-pack"]
```

The directory must contain a `directory.json` at its root. Local packs get priority 0 and always shadow remote packs.

#### Cache directory

Remote packs are cloned to `skill_cache_dir` on first use. Subsequent loads update the clone via
`git pull` only when the pack's pull freshness window has expired (see `git_pull_ttl` below).
Override the directory with the `RAILS_AI_BRIDGE_CACHE_DIR` environment variable or the config
option.

#### Git pull freshness

`git_pull_ttl` (default 86400 s = 24 h) controls how often a cached pack is refreshed via `git
pull`. The timestamp of the last successful pull is tracked in memory per pack. If the TTL window
has not elapsed, the existing clone is used as-is.

```ruby
config.registry.git_pull_ttl = 3600  # refresh packs every hour
config.registry.git_pull_ttl = 0     # always pull on every resolver rebuild
```

Pull timestamps reset when the process restarts. To force a pull on the next rebuild, run
`rails ai:skills:clear_cache` — this removes the cached clones entirely so the next build
triggers a fresh `git clone`.

#### Git operation timeout

`git_timeout` (default 30 s) limits how long any single git operation (clone, pull, checkout)
may run before it is interrupted. A `ResolutionError` is raised if the limit is exceeded,
naming the operation and pack in the message.

```ruby
config.registry.git_timeout = 10  # tighter limit for fast networks
config.registry.git_timeout = 60  # more time for slow remotes
```

#### Resolver cache TTL

The wired `Resolver` object is cached in memory to avoid re-reading the manifest and re-running
git operations on every MCP call. The default TTL is 30 minutes.

```ruby
config.registry.resolver_ttl = 300  # rebuild every 5 minutes
config.registry.resolver_ttl = 0    # disable caching (rebuild on every call)
```

Invalidate manually:

```ruby
RailsAiBridge::Registry.invalidate_resolver_cache!
```

In development, the resolver cache is invalidated automatically on every Zeitwerk code reload
via the Engine's `to_prepare` hook, so initializer changes take effect without a server restart.

### Available MCP tools

Once a registry manifest is configured:

| Tool | Description |
|------|-------------|
| `rails_list_registry type=skills` | Lists all skills across loaded packs (optional `pack:` filter) |
| `rails_list_registry type=agents` | Lists all agents/workflows across loaded packs (optional `pack:` filter) |
| `rails_list_registry type=packs` | Lists active packs with version, priority, and summary |
| `rails_resolve_skill` | Full content of a named skill or agent from the registry (priority ordering + deprecation redirects); optional `pack=` pin and `type=agent` |

### Available rake tasks

| Task | Description |
|------|-------------|
| `rails ai:skills:list` | Print skill catalog to stdout; `[json]` argument (or `FORMAT=json`) prints a `{"packs": [...], "skills": [...]}` document |
| `rails "ai:skills:resolve[pack,skill_name]"` | Resolve and print a skill's full content |
| `rails ai:skills:clear_cache` | Remove all cached pack git repositories and invalidate the resolver cache |
| `rails ai:registry:validate` | Validate the registry manifest schema; exits non-zero on the first invalid field |

Examples:

```bash
# List all skills
rails ai:skills:list

# Resolve a specific skill (pack filter is optional)
rails "ai:skills:resolve[rails,code-review]"
rails "ai:skills:resolve[,write-tests]"

# Or using env vars
PACK=rails SKILL=code-review rails ai:skills:resolve

# Clear cache after a force-push or config change
rails ai:skills:clear_cache
```

### Deprecation redirects

Packs can declare that an old skill name now points to a new one. When an AI client requests a deprecated
skill by name, the bridge transparently resolves the new skill and returns a deprecation warning.

Example `directory.json` deprecation entry:

```json
{
  "deprecated_skills": {
    "old-code-review": {
      "moved_to": "code-review",
      "message": "Renamed to code-review in v2.0",
      "removed_in": "3.0.0"
    }
  }
}
```

### Dependency validation

Packs can declare dependencies on other packs via `depends_on`. The bridge validates these at load
time. When an active pack lists a dependency that is not in the active set, a `[rails-ai-bridge]`
warning is emitted to stderr naming each missing dependency and pointing to the manifest field that
should be updated. The pack itself still loads — this is an advisory warning, not an abort.

> Transitive dependency loading (automatically pulling in a pack's `depends_on` entries) is not
> yet implemented. All required packs must be listed explicitly in `always_loaded` or the
> `skill_packs` config option.

### Cache management

```bash
rails ai:skills:clear_cache
```

Removes all cloned pack repositories from the `skill_cache_dir` and invalidates the in-memory resolver. Run this when:

- A remote pack was force-pushed and the local clone is stale
- You want to free disk space
- You changed `skill_cache_dir` and need to re-clone elsewhere

### Security

- **Path traversal guard**: skill file paths in `directory.json` are validated against the pack's base
  directory using canonical path comparison. Paths that escape the pack root are silently skipped.
- **Source validation**: `SourceParser` classifies each source string into one of three valid formats
  before any git operation. Strings that do not match are rejected with a `ResolutionError` that names
  the valid formats.
- **HTTPS/SSH only**: plain `http://` URLs are rejected. Only `https://` and `git@` (SSH) sources are
  accepted for remote packs, preventing unencrypted transmission of credentials and pack content.
- **Open3 subprocess isolation**: git operations use Open3 with array arguments — no shell interpolation.
- **Cache key sanitization**: cache directory names are derived from a sanitized source string +
  SHA256 hash to prevent filesystem collisions.
- **Stable local pack names**: local registry packs use a SHA256 digest of the directory path as their
  name suffix, so reordering `local_registry_paths` cannot silently shift pack identities.
- **Timeout protection**: all git operations are bounded by `git_timeout` (default 30 s), preventing a
  slow remote from blocking the calling thread indefinitely.
- **Local path security**: local paths are used as-is without git operations. The path traversal guard
  in the `Resolver` still applies to all file reads within the pack, regardless of source type.
