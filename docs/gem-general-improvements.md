# Gem General Improvements — Roadmap

Collected opportunities for improving the `rails-ai-bridge` gem beyond the issues already
addressed in the current session. Ordered roughly by impact vs effort.

---

## 1. Manifest Schema Validation

**Problem:** `RegistryManifest.from_file` parses JSON but does not validate the structure.
A typo in a pack entry (e.g. missing `source`) surfaces as a confusing `KeyError` or `nil`
deep in `PackResolver`, not as a clear validation failure.

**Plan:**

- Add a `RegistryManifest.validate!(data)` class method that raises `RegistryManifest::ValidationError`
  with a descriptive message on the first invalid field.
- Required top-level keys: none (empty manifest is valid).
- Required pack keys: `source`.
- Optional pack keys: `ref`, `tile`, `depends_on`, `priority`.
- Validate types: `source` is a non-empty String; `depends_on` is an Array of Strings; etc.
- Add a `rails rails_ai:registry:validate` rake task that loads the manifest and runs validation,
  suitable for use in pre-commit hooks or CI.

**Files:** `registry_manifest.rb`, `rails_ai_bridge.rake`, specs.

---

## 2. Pack Version Lock File

**Problem:** Two developers running the same registry manifest may resolve different pack content
if packs do not pin a `ref`. There is no equivalent of `Gemfile.lock` for skill packs.

**Plan:**

- After a successful resolver build, write a `config/rails_ai_bridge_registry.lock` JSON file
  containing the resolved SHA for each pack's HEAD commit:

  ```json
  {
    "rails-core-skills": { "sha": "abc123...", "resolved_at": "2025-06-01T10:00:00Z" },
    "ruby-core-skills":  { "sha": "def456...", "resolved_at": "2025-06-01T10:00:00Z" }
  }
  ```
- When the lock file is present, `SkillSourceResolver#resolve` uses the locked SHA as the
  `ref` argument, bypassing any branch-tip divergence.
- A `rails rails_ai:registry:update` task regenerates the lock (analogous to `bundle update`).
- The lock file should be committed to version control.
- `git_pull_ttl` is ignored when a lock file SHA is present — the cached commit is pinned.

**Files:** `registry_manifest.rb`, `skill_source_resolver.rb`, new `lock_file.rb`, rake task, specs.

---

## 3. RakePresenter / Agent-Facing Output

**Problem:** The `rails rails_ai:skills` rake task is currently designed for human consumption
(table layout, truncation, colour-free text). Agents calling the registry tool via MCP receive
a different, richer format. The two diverge over time.

**Plan:**

- Add an `--format=json` flag to `rails rails_ai:skills` and `rails rails_ai:registry` tasks.
- Output a stable JSON schema that agents can parse directly when the MCP server is not available
  (e.g. in CI or when writing custom tooling).
- Schema:

  ```json
  {
    "packs": [{ "name": "...", "version": "...", "summary": "...", "priority": 10 }],
    "skills": [{ "name": "...", "pack": "...", "description": "..." }]
  }
  ```
- `RakePresenter` gains a `skills_json` and `packs_json` method alongside the existing
  `skills_table` / `resolve_skill_output`.

**Files:** `rake_presenter.rb`, `rails_ai_bridge.rake`, specs.

---

## 4. Full SHA-256 for compute_cache_key

**Problem:** `SkillSourceResolver.compute_cache_key` currently uses only the first 16 hex
characters of the SHA-256 digest (`hexdigest[0..15]`). This is 64 bits of entropy — sufficient
for collision avoidance across a handful of packs, but inconsistent with the rest of the gem
(which uses full 64-hex SHA-256 digests for fingerprinting).

**Plan:**

- Change `hexdigest(source)[0..15]` to `hexdigest(source)` (full 64-character hash).
- This is a breaking change for any existing cached directories. Document in CHANGELOG.
- Existing caches under the old key format will become orphaned; document that users should
  run `rm -rf ~/.rails-ai-bridge/cache` after upgrading.
- Alternatively, implement a migration: scan the cache dir for directories matching the old
  key pattern and rename them to the new format.

**Files:** `skill_source_resolver.rb`, `CHANGELOG.md`, specs.

---

## 5. Transitive depends_on Loading

**Problem:** `PackDefinition#depends_on` is parsed and stored but never acted upon.
`PackResolver` currently only emits a warning when a dependency is missing from the active set.
There is no automatic dependency resolution.

**Plan:**

- In `PackResolver#gather_active_packs`, after computing the initial active set, iterate over
  all active packs and union their `depends_on` into the active set. Repeat until stable
  (fixed-point iteration), capped at a reasonable depth (e.g. 10) to prevent infinite loops
  from circular dependencies.
- Detect and report circular dependencies with a clear error message.
- Add a config flag `config.registry.auto_load_dependencies = true` (default `false` initially
  to avoid surprising behavior, then `true` in a future major version).

**Files:** `pack_resolver.rb`, `config/registry.rb`, specs.

---

## 6. HTTP Transport Authentication for MCP

**Problem:** `http_mcp_token` is a static bearer token. JWTs with short expiry are not supported
for the registry MCP endpoint, making rotation hard.

**Plan:** Already partially addressed by `mcp_jwt_decoder` config; document the pattern in
`docs/mcp-security.md` with a worked example using `JWT.decode`.

---

## 7. pack_resolver_spec.rb — depends_on Warning Coverage

The warning emitted by `warn_missing_dependencies` is not yet tested. Add:

```ruby
context 'when an active pack declares a missing dependency' do
  it 'emits a warning naming the pack and missing dependency' do
    expect { resolver.resolve(manifest, ['pack-with-dep'], ...) }
      .to output(/depends on.*'missing-dep'/).to_stderr
  end

  it 'still loads the pack despite the missing dependency' do
    result = resolver.resolve(manifest, ['pack-with-dep'], ...)
    expect(result.packs.map(&:name)).to include('pack-with-dep')
  end
end
```

---

## 8. Observability — Structured Logging

**Problem:** Errors from git operations surface as raised exceptions with no structured context.
In production it is hard to correlate a `ResolutionError` with a specific pack or commit.

**Plan:**

- Accept an optional `logger:` parameter in `SkillSourceResolver#initialize`.
- Before each git operation, log at DEBUG: `{ op: :clone, source:, cache_path: }`.
- On success, log at INFO: `{ op: :clone, duration_ms:, cache_path: }`.
- On failure, log at ERROR: `{ op: :clone, source:, error: message }`.
- Default logger: `Rails.logger` when in a Rails context, `Logger.new($stderr)` otherwise.
