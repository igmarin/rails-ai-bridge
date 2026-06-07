# Offline Mode — Design Plan

## Problem

The registry resolver currently requires network access on every fresh start to clone or pull
skill pack repositories. In offline environments (CI without egress, corporate networks with
proxy restrictions, air-gapped machines) this makes the registry unusable.

## Goals

1. Allow a pre-populated cache to be used without any git operations.
2. Allow operators to ship a vendored snapshot of packs alongside their application.
3. Produce a clear, actionable error message when a pack is missing and network is unavailable.

## Non-Goals

- Partial offline (some packs online, some local) — the existing `local_registry_paths` already
  covers this; offline mode is a broader system-level switch.
- Automatic cache population — that still requires a prior online `rails rails_ai:registry:pull`.

---

## Proposed Configuration API

```ruby
# config/initializers/rails_ai_bridge.rb
RailsAiBridge.configure do |config|
  config.registry.offline = true          # raise ResolutionError instead of cloning/pulling
  # config.registry.offline = :warn       # log a warning but continue (use stale cache)
end
```

Default: `false` (current behavior).

---

## Implementation Plan

### Phase 1 — Config flag

- Add `attr_accessor :offline` to `Config::Registry` with default `false`.
- Document the three valid values (`false`, `true`, `:warn`).

### Phase 2 — Wire into SkillSourceResolver

In `SkillSourceResolver#resolve`:

```ruby
if offline?
  raise ResolutionError, offline_error(source) unless File.exist?(cache_path)
  return cache_path                           # use cache as-is
end
```

In `#perform_pull` and `#perform_clone`:

```ruby
if offline? == :warn
  warn "[rails-ai-bridge] Offline mode :warn — skipping git #{op} for pack: #{source}"
  return
end
```

The `offline?` helper reads from the injected config; `DefaultGitRunner` is not called at all.

### Phase 3 — Rake task: `rails rails_ai:registry:pull`

A new rake task that forces a full pull of all configured packs regardless of TTL:

```ruby
task pull: :environment do
  resolver = RailsAiBridge::Registry.build_resolver_uncached(config)
  puts "Pulled #{resolver&.packs&.count || 0} pack(s) to #{config.skill_cache_dir}"
end
```

Running this before switching `offline: true` ensures the cache is populated.

### Phase 4 — Vendored pack snapshot

Document a pattern where packs are committed to `vendor/skill_packs/` and each pack entry
in the registry manifest uses a `local_registry_paths` entry pointing there. No git at all.

### Phase 5 — CI guidance

Add a GitHub Actions example that:

1. Caches `~/.rails-ai-bridge/cache` across runs keyed on the manifest hash.
2. Runs `rails rails_ai:registry:pull` only on cache miss.
3. Sets `RAILS_AI_BRIDGE_OFFLINE=true` (mapped to `config.registry.offline = true`)
   for the test job to prevent accidental pulls.

---

## Error Messages

| Scenario | Message |
|----------|---------|
| `offline: true`, pack not cached | `"Offline mode is enabled. Run \`rails rails_ai:registry:pull\` to populate the cache before going offline."` |
| `offline: :warn`, pack not cached | Warning logged, pack skipped, no raise |
| Network error + `offline: false` | Existing `ResolutionError` with git stderr |

---

## Files to Create / Modify

| File | Change |
|------|--------|
| `lib/rails_ai_bridge/config/registry.rb` | Add `offline` attr, default `false` |
| `lib/rails_ai_bridge/registry/skill_source_resolver.rb` | Guard clone/pull with offline check |
| `lib/rails_ai_bridge/tasks/rails_ai_bridge.rake` | Add `registry:pull` task |
| `spec/lib/rails_ai_bridge/registry/skill_source_resolver_spec.rb` | Add offline mode contexts |
| `docs/skill-registry-guide.md` | Document offline workflow |

---

## Open Questions

1. Should `offline: true` also suppress `checkout_ref`? (Yes — if cache exists, trust it.)
2. Should the rake pull task honour `git_pull_ttl`? (No — it is an explicit override.)
3. Should ENV var `RAILS_AI_BRIDGE_OFFLINE` map to the config? (Yes, for CI convenience.)
