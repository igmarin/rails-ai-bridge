# Registry Resolution Reference

rails-ai-bridge can load **skill packs** — curated collections of agent skills and workflows — from versioned git repositories and make them discoverable via MCP tools and rake tasks.

> **New to skill packs?** Read the [Skill Registry Guide](skill-registry-guide.md) first. It covers concepts, step-by-step setup, source formats, version pinning, and troubleshooting.

## What a skill pack is

A skill pack is a git repository that contains:

- A **`directory.json`** manifest listing available skills and agents
- Markdown skill files (e.g. `skills/code-review.md`) referenced by the manifest
- Optional deprecation redirects when skills are renamed

When a pack is loaded, its skills and agents appear in `rails_list_registry`, and any skill can be resolved to full content for an AI client.

## Quick start

**1. Create the registry manifest** at `config/rails_ai_bridge_registry.json`:

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
  config.registry.registry_manifest_path = "config/rails_ai_bridge_registry.json"
end
```

**3. Verify** packs are loaded:

```bash
rails ai:skills:list
```

## Registry manifest format

| Field | Type | Description |
|-------|------|-------------|
| `version` | String | Manifest schema version (currently `"1.0.0"`) |
| `packs` | Object | Map of pack name → pack definition |
| `default_stack` | Array | Pack names loaded when no framework is detected |

### Pack definition fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `source` | String | Yes | — | Pack source: local path, full git URL, or `owner/repo` GitHub shorthand |
| `tile` | String | No | `"directory.json"` | Relative path to the pack's catalog file |
| `always_loaded` | Boolean | No | `false` | Load this pack regardless of framework detection |
| `depends_on` | Array | No | `[]` | Other pack names this pack requires |
| `ref` | String | No | `nil` | Git branch, tag, or SHA to check out; `nil` uses the default branch |

### Source formats

Three formats are accepted for the `source` field:

| Format | Example |
|--------|---------|
| Local path | `/abs/path`, `./relative`, `../sibling` |
| HTTPS URL | `https://github.com/org/repo.git` |
| SSH URL | `git@github.com:org/repo.git` |
| GitHub shorthand | `owner/repo` (expanded to `https://github.com/owner/repo.git`) |

> **Note:** plain `http://` URLs are rejected to prevent unencrypted transmission of credentials
> and pack content. Use `https://` or `git@` (SSH) instead.

## Priority rules

Packs are assigned priorities based on their name (case-insensitive exact match). Lower number = higher priority.

| Pack name | Priority | Reasoning |
|-----------|----------|-----------|
| `local_*` (local registries) | 0 | Highest — local overrides always win |
| `rails`, `hanami` | 10 | Framework-specific packs shadow generic ones |
| `core` | 20 | Core packs provide defaults |
| Any other name | 30 | Lowest — third-party or custom packs |

When the same skill name appears in multiple packs, the version from the **highest priority** pack (lowest number) is returned.

Note: only exact name matches qualify for high/medium priority. `rails-extras` gets priority 30.

## Configuration options

All options live under `config.registry.*`:

| Option | Default | Description |
|--------|---------|-------------|
| `registry_manifest_path` | `"config/rails_ai_bridge_registry.json"` | Path to the registry manifest JSON |
| `skill_cache_dir` | `~/.rails-ai-bridge/cache` | Directory for caching cloned git repositories |
| `skill_packs` | `nil` | Explicit list of pack names to load, or `nil` for auto-detection |
| `local_registry_paths` | `[]` | Local directory paths containing a `directory.json` (loaded at priority 0) |
| `resolver_ttl` | `1800` | Seconds to keep the wired `Resolver` in memory before rebuilding (default: 30 min) |
| `git_pull_ttl` | `86400` | Seconds between `git pull` refreshes per cached pack (default: 24 h). Set to `0` to pull on every resolver rebuild |
| `git_timeout` | `30` | Seconds before a git operation (clone, pull, checkout) is forcibly interrupted and a `ResolutionError` raised |

### Auto-detection

When `skill_packs` is `nil`, the bridge auto-detects the framework from your `Gemfile`:

- Rails detected → loads the `rails` pack
- Hanami detected → loads the `hanami` pack
- Neither detected → falls back to `default_stack` from the manifest

Set `skill_packs` explicitly to bypass auto-detection:

```ruby
config.registry.skill_packs = %w[rails core]
```

### Local registry paths

Use `local_registry_paths` to load packs from local directories (useful during pack development):

```ruby
config.registry.local_registry_paths = ["/path/to/my-local-pack"]
```

The directory must contain a `directory.json` at its root. Local packs get priority 0 and always shadow remote packs.

### Cache directory

Remote packs are cloned to `skill_cache_dir` on first use. Subsequent loads update the clone via
`git pull` only when the pack's pull freshness window has expired (see `git_pull_ttl` below).
Override the directory with the `RAILS_AI_BRIDGE_CACHE_DIR` environment variable or the config
option.

### Git pull freshness

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

### Git operation timeout

`git_timeout` (default 30 s) limits how long any single git operation (clone, pull, checkout)
may run before it is interrupted. A `ResolutionError` is raised if the limit is exceeded,
naming the operation and pack in the message.

```ruby
config.registry.git_timeout = 10  # tighter limit for fast networks
config.registry.git_timeout = 60  # more time for slow remotes
```

### Resolver cache TTL

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

## Available MCP tools

Once a registry manifest is configured:

| Tool | Description |
|------|-------------|
| `rails_list_registry type=skills` | Lists all skills across loaded packs (optional `pack:` filter) |
| `rails_list_registry type=agents` | Lists all agents/workflows across loaded packs (optional `pack:` filter) |
| `rails_list_registry type=packs` | Lists active packs with version, priority, and summary |

## Available rake tasks

| Task | Description |
|------|-------------|
| `rails ai:skills:list` | Print skill catalog to stdout |
| `rails "ai:skills:resolve[pack,skill_name]"` | Resolve and print a skill's full content |
| `rails ai:skills:clear_cache` | Remove all cached pack git repositories and invalidate the resolver cache |

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

## Deprecation redirects

Packs can declare that an old skill name now points to a new one. When an AI client requests a deprecated skill by name, the bridge transparently resolves the new skill and returns a deprecation warning.

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

## Dependency validation

Packs can declare dependencies on other packs via `depends_on`. The bridge validates these at load
time. When an active pack lists a dependency that is not in the active set, a `[rails-ai-bridge]`
warning is emitted to stderr naming each missing dependency and pointing to the manifest field that
should be updated. The pack itself still loads — this is an advisory warning, not an abort.

> Transitive dependency loading (automatically pulling in a pack's `depends_on` entries) is not
> yet implemented. All required packs must be listed explicitly in `always_loaded` or the
> `skill_packs` config option.

## Cache management

```bash
rails ai:skills:clear_cache
```

Removes all cloned pack repositories from the `skill_cache_dir` and invalidates the in-memory resolver. Run this when:

- A remote pack was force-pushed and the local clone is stale
- You want to free disk space
- You changed `skill_cache_dir` and need to re-clone elsewhere

## Security

- **Path traversal guard**: skill file paths in `directory.json` are validated against the pack's base directory using canonical path comparison. Paths that escape the pack root are silently skipped.
- **Source validation**: `SourceParser` classifies each source string into one of three valid formats before any git operation. Strings that do not match are rejected with a `ResolutionError` that names the valid formats.
- **HTTPS/SSH only**: plain `http://` URLs are rejected. Only `https://` and `git@` (SSH) sources are accepted for remote packs, preventing unencrypted transmission of credentials and pack content.
- **Open3 subprocess isolation**: git operations use Open3 with array arguments — no shell interpolation.
- **Cache key sanitization**: cache directory names are derived from a sanitized source string + SHA256 hash to prevent filesystem collisions.
- **Stable local pack names**: local registry packs use a SHA256 digest of the directory path as their name suffix, so reordering `local_registry_paths` cannot silently shift pack identities.
- **Timeout protection**: all git operations are bounded by `git_timeout` (default 30 s), preventing a slow remote from blocking the calling thread indefinitely.
- **Local path security**: local paths are used as-is without git operations. The path traversal guard in the `Resolver` still applies to all file reads within the pack, regardless of source type.
