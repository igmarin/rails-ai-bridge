# Skill Registry Guide

This guide walks you through setting up and using the rails-ai-bridge skill registry. If you want the dry technical reference instead, see [docs/registry-resolution.md](registry-resolution.md).

## What problem this solves

Every Rails team has conventions: how they name service objects, how they structure tests, what patterns they enforce in code review. Without the skill registry, an AI assistant rediscovers those conventions from scratch every session — or worse, ignores them.

Skill packs let you codify those conventions once as agent instruction files and load them automatically into any project's MCP context. A code-review skill written for your team's Rails style is available in every repo, every session, and every AI tool that speaks MCP.

---

## Mental model

A **skill pack** is a git repository containing:

- A **`directory.json`** catalog that lists available skills and agents
- **Markdown files** for each skill (e.g. `skills/code-review.md`)
- Optional **deprecation redirects** when skills are renamed

The skill registry in your Rails app is a **`config/rails_ai_bridge_registry.json`** manifest that tells rails-ai-bridge which packs to load, where to find them, and how to prioritize them when two packs define a skill with the same name.

---

## Quick start (3 steps)

### Step 1 — Create the registry manifest

Create `config/rails_ai_bridge_registry.json` in your Rails app:

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

The `source` field is a GitHub `owner/repo` shorthand. The `tile` field is optional — it defaults to `directory.json` at the root of the pack.

### Step 2 — Configure the bridge

In `config/initializers/rails_ai_bridge.rb`:

```ruby
RailsAiBridge.configure do |config|
  config.registry.registry_manifest_path = "config/rails_ai_bridge_registry.json"
end
```

### Step 3 — Verify packs are loaded

```bash
rails ai:skills:list
```

You should see a table of skills with their pack name and description. If packs are not yet cached locally, the first run clones them from GitHub.

---

## Source formats

The `source` field in a pack definition accepts three formats:

| Format | Example | When to use |
|--------|---------|-------------|
| Local path | `/Users/alice/my-skills` or `./local-pack` | Pack development, monorepo |
| HTTPS URL | `https://github.com/org/skills.git` | Non-GitHub remotes; most common for public repos |
| SSH URL | `git@github.com:org/skills.git` | Private repos or when SSH keys are configured |
| GitHub shorthand | `igmarin/rails-agent-skills` | Shortest form — expanded to HTTPS automatically |

```json
{
  "packs": {
    "local-override": {
      "source": "/Users/alice/dev/my-skills"
    },
    "via-https": {
      "source": "https://gitlab.com/myorg/skills.git"
    },
    "via-ssh": {
      "source": "git@gitlab.com:myorg/skills.git"
    },
    "via-shorthand": {
      "source": "igmarin/ruby-core-skills"
    }
  }
}
```

Local paths are never cloned — the directory is used directly. Git URL and shorthand sources are cloned to the skill cache directory.

> **`http://` is not accepted.** Plain HTTP URLs are rejected to prevent credentials and pack content from being transmitted unencrypted. Use `https://` or SSH (`git@`) instead.

---

## Priority rules

When two packs define a skill with the same name, the version from the **highest priority** pack wins. Priority is assigned by pack name (case-insensitive matching):

| Pack name | Priority | Reason |
|-----------|----------|--------|
| `local_*` (local registries) | 0 | Always win — local overrides |
| `rails` or `hanami` | 10 | Framework-specific packs override generic ones |
| `core` | 20 | Core defaults |
| Any other name | 30 | Third-party or custom packs |

**Note:** Only exact name matches get the boosted priority. A pack named `rails-extras` gets priority 30, not 10.

To override a skill from any remote pack, add a local registry path:

```ruby
config.registry.local_registry_paths = ["/path/to/my-local-pack"]
```

Local registry packs always get priority 0.

---

## Version pinning

Pin a pack to a specific branch, tag, or commit SHA using the `ref` field:

```json
{
  "packs": {
    "rails": {
      "source": "igmarin/rails-agent-skills",
      "ref": "v1.2.0"
    },
    "core": {
      "source": "igmarin/ruby-core-skills",
      "ref": "main"
    }
  }
}
```

When `ref` is set, rails-ai-bridge runs `git checkout <ref>` after cloning or pulling. Without `ref`, the default branch (usually `main`) is used.

**When to pin:**
- Production deployments where you want deterministic skill behavior
- When a pack update broke your workflow
- When you need to test against a specific version before upgrading

---

## The `directory.json` format

Each skill pack repository should have a `directory.json` at its root. Here is an annotated example:

```json
{
  "name": "rails-agent-skills",
  "version": "1.2.0",
  "summary": "Rails development skills for AI agents",
  "depends_on": ["core"],
  "skills": {
    "code-review": {
      "path": "skills/code-review.md",
      "description": "Review Rails code against team conventions."
    },
    "write-tests": {
      "path": "skills/write-tests.md",
      "description": "Write RSpec tests for Rails models and services."
    }
  },
  "agents": {
    "tdd-workflow": {
      "path": "agents/tdd-workflow.md",
      "description": "Full TDD cycle from failing test to passing implementation."
    }
  },
  "deprecated_skills": {
    "review-rails-code": {
      "moved_to": "code-review",
      "message": "Renamed to code-review in v1.1",
      "removed_in": "2.0.0"
    }
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | String | Pack identifier |
| `version` | String | SemVer version string |
| `summary` | String | Brief description shown in `rails_list_registry type=packs` |
| `depends_on` | Array | Pack names this pack needs loaded first |
| `skills` | Object | Map of skill name → `{ path, description }` |
| `agents` | Object | Map of agent name → `{ path, description }` |
| `deprecated_skills` | Object | Rename redirects for old skill names |

Skill and agent paths are relative to the pack's root directory.

---

## MCP tool reference

Once a registry manifest is configured, use `rails_list_registry` to query the catalog:

### List all skills

```bash
rails_list_registry type=skills
```

Returns a markdown table of all skills across all loaded packs with name, pack, and description.

### Filter by pack

```bash
rails_list_registry type=skills pack=rails
rails_list_registry type=agents pack=core
```

Narrows results to one pack.

### List active packs

```bash
rails_list_registry type=packs
```

Returns all loaded packs with name, version, priority, and summary. Use this to confirm which packs are active and what their priorities are.

---

## Rake task reference

### List skills

```bash
rails ai:skills:list
```

Prints a skills table to stdout with skill name, pack, and truncated description. Good for quickly checking what is loaded.

### Resolve a skill

```bash
rails "ai:skills:resolve[rails,code-review]"
```

Resolves and prints the full content of a skill. The pack argument is optional and used only for a mismatch warning:

```bash
rails "ai:skills:resolve[,write-tests]"         # resolve by name, no pack filter
PACK=rails SKILL=code-review rails ai:skills:resolve   # same via env vars
```

### Clear the cache

```bash
rails ai:skills:clear_cache
```

Removes all locally cached pack repositories from the skill cache directory and invalidates the in-memory resolver cache. Run this when:

- A remote pack was force-pushed and the cache is stale
- You want to free disk space
- You changed the `skill_cache_dir` configuration

---

## Git operation settings

### Pull freshness window (`git_pull_ttl`)

By default, a cached pack is refreshed via `git pull` at most once every 24 hours. This avoids
redundant network calls — skill pack files are documentation and rarely change between releases.

```ruby
config.registry.git_pull_ttl = 3600  # refresh every hour
config.registry.git_pull_ttl = 0     # always pull on every resolver rebuild (old behaviour)
```

Pull timestamps are tracked in memory per pack and reset when the process restarts. To force an
immediate re-pull without restarting, run `rails ai:skills:clear_cache` — this removes cached
clones entirely so the next build does a fresh `git clone`.

### Git operation timeout (`git_timeout`)

All git operations (clone, pull, checkout) have a 30-second timeout by default. If the limit is
exceeded, a `ResolutionError` is raised — the server stays responsive even when a remote is slow
or unreachable.

```ruby
config.registry.git_timeout = 10  # faster fail on fast networks
config.registry.git_timeout = 60  # more time for large repos or slow remotes
```

---

## Resolver cache

rails-ai-bridge caches the wired `Resolver` object in memory to avoid re-reading the manifest
and re-running git operations on every MCP tool call.

**Default TTL:** 30 minutes (1800 seconds).

Override in your initializer:

```ruby
config.registry.resolver_ttl = 300  # rebuild every 5 minutes
```

Set to `0` to disable caching (rebuilds on every call — only useful in development):

```ruby
config.registry.resolver_ttl = 0
```

The cache is invalidated automatically by `rails ai:skills:clear_cache`. You can also invalidate
it programmatically:

```ruby
RailsAiBridge::Registry.invalidate_resolver_cache!
```

In development, the cache is also invalidated automatically on every Zeitwerk code reload so that
initializer changes take effect immediately.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `rails ai:skills:list` shows "No registry manifest found" | Manifest file does not exist or path is wrong | Create `config/rails_ai_bridge_registry.json` or check `config.registry.registry_manifest_path` |
| Git clone fails with "not found" | Pack source URL is wrong or repo is private | Check the `source` field; for private repos use a full SSH URL `git@github.com:org/repo.git` |
| `Invalid source format` error mentioning `http://` | Pack source uses plain HTTP | Change `source` to `https://` or `git@` — plain HTTP is not accepted |
| Pack loads but shows 0 skills | `directory.json` is missing or has wrong path | Check the root of the cloned pack for `directory.json`; set `tile:` field if the file is elsewhere |
| Skill resolves from wrong pack | Priority mismatch | Use `rails_list_registry type=packs` to see priorities; use local registry or explicit `skill_packs` to override |
| Stale skills after pack update | Resolver cache is warm or pull TTL has not elapsed | Run `rails ai:skills:clear_cache` to force a re-clone on the next build |
| Pack is not re-fetched even after `resolver_ttl` expired | Pack was cloned recently — `git_pull_ttl` (24 h) is still fresh | Run `rails ai:skills:clear_cache` or set `git_pull_ttl: 0` temporarily |
| `git checkout <ref>` failed | Invalid ref or detached HEAD issue | Verify the `ref` value matches a branch, tag, or SHA in the remote repo |
| Git operation hangs / server request times out | Slow or unreachable remote | Reduce `git_timeout` to fail faster; check network connectivity to the remote |
| Warning: "Pack '…' depends on '…' which is not in the active pack set" | A loaded pack has an unsatisfied `depends_on` entry | Add the missing pack name to `always_loaded` or `skill_packs` in your manifest |

---

## Security model

- **Path traversal guard**: skill file paths in `directory.json` are validated against the pack's base directory. A path like `../../etc/passwd` is silently skipped.
- **Source validation**: all source formats are validated by `SourceParser` before any git operation. Strings that do not match a known format raise `ResolutionError` before any subprocess is spawned.
- **HTTPS/SSH only**: plain `http://` URLs are rejected at parse time to prevent unencrypted transmission of credentials and pack content.
- **Subprocess isolation**: git operations use Open3 with array arguments — no shell interpolation.
- **Timeout protection**: all git operations are bounded by `git_timeout` (default 30 s) so a slow remote cannot block the calling thread indefinitely.
- **Cache key sanitization**: local cache directory names are derived from a sanitized source string plus a SHA256 hash suffix to prevent filesystem collisions.
- **Stable local pack names**: local registry pack names use a SHA256 digest of the directory path, so reordering `local_registry_paths` cannot silently shift pack identities.
- **Local path trust**: local paths are used directly without git operations. The path traversal guard in the Resolver still applies to file reads within a local pack.
