# Plan 2: Port Registry Resolution from Rust Runtime to rails-ai-bridge

**Status:** Complete ✅ — implemented via PRs #40–#45
**Priority:** After Plan 1
**Estimated effort:** 4 weeks
**Depends on:** Plan 1 (agent-mcp-runtime archived)

> **Completion note (2026-08-10):** All success criteria shipped. See
> [`port-registry-resolution.md`](port-registry-resolution.md) for as-built decisions and deltas, and
> [`registry-resolution.md`](registry-resolution.md) for user-facing documentation. Naming deltas from
> this plan: rake tasks shipped as `ai:skills:list` / `ai:skills:resolve[pack,name]` (planned:
> `ai:list_skills` / `ai:resolve_skill`); configuration lives under `config.registry.*`
> (`Config::Registry`); the MCP surface is the unified `rails_list_registry` tool plus
> `rails_resolve_skill`; git operations use `Open3` (stdlib) — no `git` gem dependency.

## Objective

Port the registry resolution logic from `agent-mcp-runtime` (Rust) into `rails-ai-bridge` (Ruby). This enables the bridge to resolve skill packs from git repositories, handle priority-based loading, and support deprecation redirects — all necessary for the future skill compiler feature.

## Components to Port

### 1. New module: `lib/rails_ai_bridge/registry/`

#### `lib/rails_ai_bridge/registry/manifest.rb`
- Port `RegistryManifest` struct from Rust (version, packs, default_stack, context_providers)
- Port `PackDefinition` struct (source, tile, always_loaded, depends_on)
- Port `ContextProviderDefinition` and `ContextToolSpec` (for future context provider integration)
- Use JSON parsing with `json` gem (already in rails-ai-bridge dependencies)

#### `lib/rails_ai_bridge/registry/tile_manifest.rb`
- Port `TileManifest` struct (name, version, summary, depends_on, skills, agents, deprecated_skills)
- Port `SkillEntry` and `AgentEntry` structs
- Port `DeprecatedEntry` struct (moved_to, message, removed_in)

#### `lib/rails_ai_bridge/registry/git_source_resolver.rb`
- Port `SkillSourceResolver` from Rust
- Implement git clone/pull using `git` gem or shell commands
- Cache directory: `~/.rails-ai-bridge/cache/` (instead of `~/.agent-mcp-runtime/cache/`)
- Support local path resolution (sibling directories for development)
- Implement `GitRunner` trait pattern with a default implementation and test mock

#### `lib/rails_ai_bridge/registry/pack_detector.rb`
- Port `PackDetector` from Rust
- Parse Gemfile to detect Rails vs Hanami
- Return array of detected frameworks

#### `lib/rails_ai_bridge/registry/pack_resolver.rb`
- Port `PackResolverService` logic
- Implement priority-based pack loading:
  - Priority 0: Local registries (--registry flag)
  - Priority 10: Framework packs (rails, hanami)
  - Priority 20: Core pack (always_loaded)
  - Priority 30: Default stack (planning)
- Handle explicit pack overrides
- Load tile.json manifests from resolved sources
- Return `RegistryResolver` instance

#### `lib/rails_ai_bridge/registry/resolver.rb`
- Port `RegistryResolver` from Rust
- Implement `LoadedPack` struct (name, tile, base_path, priority)
- Implement `ResolvedSkill` struct (name, pack, path, content)
- Implement `SkillSummary` struct (name, pack, description)
- Implement `resolve_skill(name)` with deprecation redirect handling
- Implement `resolve_agent(name)`
- Implement `list_skills()` with deduplication by priority
- Implement `validate_dependencies()` to warn on missing dependencies
- Sort packs by priority (ascending = higher priority)

#### `lib/rails_ai_bridge/registry.rb`
- Main registry module that requires all submodules
- Public API entry point

### 2. Integration with rails-ai-bridge

**Add to `lib/rails_ai_bridge.rb`:**
- Require the new registry module
- Add convenience method `RailsAiBridge.resolve_skill(pack_name, skill_name)`
- Add convenience method `RailsAiBridge.list_skills()`

**Create new Rake task: `lib/rails_ai_bridge/tasks/registry.rake`**

```ruby
namespace :rails_ai_bridge do
  desc "List all available skills from configured packs"
  task list_skills: :environment do
    # Use registry resolver to list skills
  end

  desc "Resolve a specific skill"
  task :resolve_skill, [:pack, :skill] => :environment do |t, args|
    # Resolve and print skill content
  end
end
```

### 3. Configuration

**Add to `lib/rails_ai_bridge/configuration.rb`:**
- `registry_manifest_path` — Path to registry.json (default: `config/rails_ai_bridge_registry.json`)
- `skill_cache_dir` — Path to git cache directory (default: `~/.rails-ai-bridge/cache`)
- `skill_packs` — Array of explicit pack names to load (optional)
- `local_registry_paths` — Array of local registry directories (optional)

### 4. Tests

**Create spec directory: `spec/rails_ai_bridge/registry/`**
- `manifest_spec.rb`
- `tile_manifest_spec.rb`
- `git_source_resolver_spec.rb` (with mock git runner)
- `pack_detector_spec.rb`
- `pack_resolver_spec.rb`
- `resolver_spec.rb`

Use the Rust tests in `agent-mcp-runtime/src/registry/pack_resolver.rs` and `resolver.rs` as reference for test cases.

### 5. Documentation

**Create `docs/registry-resolution.md`** inside rails-ai-bridge:
- Explain the registry resolution system
- Document priority rules
- Provide example registry.json configuration
- Document configuration options

### 6. Dependencies

Add to `rails-ai-bridge.gemspec` if not already present:
- `git` gem (for git operations) — check if already present
- Ensure `json` gem is available (standard library in Ruby 3+)

## Implementation Order

1. **Week 1:** Create manifest and tile_manifest structs with tests; create git_source_resolver with mock for tests
2. **Week 2:** Create pack_detector and pack_resolver with tests
3. **Week 3:** Create resolver with tests; integrate with rails-ai-bridge main module
4. **Week 4:** Add Rake tasks, configuration, and documentation

## Notes

- The existing `ruby-skill-bench` has a `PackResolver` class that does similar work. Review it for patterns but don't directly copy — the bridge version needs git resolution and priority handling that the bench version lacks.
- The Rust runtime uses async/await. Ruby doesn't have this — use synchronous git operations.
- Cache directory should be `~/.rails-ai-bridge/cache/` to avoid conflicts with the archived runtime.
- Framework detection: just check Gemfile for `'rails'` or `'hanami'` gems.
- Deprecation handling is critical for the skill migration from `rails-agent-skills` to `ruby-core-skills` already in progress.

## Success Criteria

- [x] All 6 registry modules created with passing specs (323 registry/config/tool examples green, 2026-08-10)
- [x] `rails ai:skills:list` Rake task works (shipped name; planned as `ai:list_skills`)
- [x] `rails "ai:skills:resolve[pack,name]"` Rake task works (shipped name; planned as `ai:resolve_skill[pack,name]`)
- [x] Documentation written (`docs/registry-resolution.md`)
- [x] Priority-based resolution handles core/rails/hanami/planning correctly
- [x] Deprecation redirects work (e.g., old skill name → new location)
