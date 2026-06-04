# Port Registry Resolution from Rust Runtime to rails-ai-bridge

**Status:** In progress — PR 1 completed ✅, PR 2 completed ✅, PR 3 next
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
| MCP tools | `rails_list_skills`, `rails_list_agents`, `rails_list_packs` included; `rails_use_skill` / `rails_use_agent` **deferred** |
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

### PR 3 — Pack resolver + registry resolver

**Files:**
- `lib/rails_ai_bridge/registry/pack_resolver.rb` — `PackResolverService`; priority-based loading;
  auto-detect or explicit packs; local registry support
- `lib/rails_ai_bridge/registry/resolver.rb` — `RegistryResolver` with `LoadedPack`, `ResolvedSkill`,
  `SkillSummary`; `resolve_skill`, `resolve_agent`, `list_skills`, `list_agents`, `validate_dependencies`,
  `check_deprecated`, `active_packs`
- `spec/lib/rails_ai_bridge/registry/pack_resolver_spec.rb`
- `spec/lib/rails_ai_bridge/registry/resolver_spec.rb`

**Notes:**
- Priorities hardcoded: `local=0`, `rails/hanami=10`, `core=20`, `other=30`
- `resolve_skill` handles deprecation redirect transparently
- Path traversal guard: resolved path must be a descendant of pack `base_path`
- Port all test cases from `pack_resolver.rs` and `resolver.rs` Rust tests (priority wins, deprecation redirect,
  dependency validation, local registry override)

### PR 4 — Configuration + integration

**Files:**
- `lib/rails_ai_bridge/config/registry.rb` — `Config::Registry` sub-object
  - `registry_manifest_path` (default: `config/rails_ai_bridge_registry.json`)
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
- `lib/rails_ai_bridge/tools/rails_list_skills_tool.rb`
- `lib/rails_ai_bridge/tools/rails_list_agents_tool.rb`
- `lib/rails_ai_bridge/tools/rails_list_packs_tool.rb`
- `spec/lib/rails_ai_bridge/tools/rails_list_skills_tool_spec.rb`
- `spec/lib/rails_ai_bridge/tools/rails_list_agents_tool_spec.rb`
- `spec/lib/rails_ai_bridge/tools/rails_list_packs_tool_spec.rb`
- `docs/registry-resolution.md` — user-facing docs (priority rules, example registry.json, config options)

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

- [ ] All registry modules created with passing specs (PR 1–3)
- [ ] `Config::Registry` wired and documented (PR 4)
- [ ] `rails_ai_bridge:list_skills` and `rails_ai_bridge:resolve_skill[pack,name]` Rake tasks work (PR 5)
- [ ] `rails_list_skills`, `rails_list_agents`, `rails_list_packs` MCP tools exposed (PR 5)
- [ ] `docs/registry-resolution.md` written (PR 5)
- [ ] Priority-based resolution handles core/rails/hanami/planning correctly
- [ ] Deprecation redirects work (old skill name → new location)
- [ ] Path traversal guard enforced in resolver
- [ ] `CHANGELOG.md` updated in every PR
- [ ] `README.md` updated in PR 4 and PR 5
- [ ] `UPGRADING.md` updated if breaking changes are introduced
- [ ] All PRs pass Qodo + CodeRabbit review gates