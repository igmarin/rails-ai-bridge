# Implementation Plan: rails-ai-bridge v2.0.0

Based on: `prd-v2-architecture-and-quality.md`

## Work Type

Rails engine gem — refactoring internal architecture + feature parity across
serializers + dependency updates. No changes to public configuration DSL.

## Dependency Graph & Sequencing Rationale

```
Phase 1 (E) — Dependency housekeeping      [no code deps, unblocks linting]
    |
Phase 2 (A) — Serializer parity            [small, self-contained, proves patterns]
    |
Phase 3 (B) — Serializer Metz refactoring  [needs Phase 2 done to avoid rework]
    |
Phase 4 (C) — Configuration refactoring    [needs Phase 3: serializers must inject config]
    |
Phase 5 (D) — Tools & Introspector refactoring  [independent of B/C, but after A for column hints]
    |
Phase 6 (F) — Coverage, CHANGELOG, version bump [last — everything must be stable]
```

**Why this order:**
- Phase 1 first: dependency updates are low-risk, unblock rubocop improvements,
  and set the CI baseline for all subsequent phases.
- Phase 2 before Phase 3: adding complexity sort and test commands to Cursor/
  Windsurf now means Phase 3 refactoring extracts *uniform* code, not
  inconsistent code. Otherwise we'd refactor first and then have to touch the
  same files again for parity.
- Phase 3 before Phase 4: serializers must accept injected config before we can
  split Configuration. If we split config first, serializers still query the
  global — we'd wire up injection twice.
- Phase 5 can run in parallel with Phase 3/4 if needed, but sequencing it after
  avoids merge conflicts in shared files.

---

## Phases

### Phase 1: Dependency & Compatibility (Pillar E)

**PR name:** `v2-dependencies`

- **Target behavior:** Gemspec and Gemfile use current stable versions. YARD is
  either wired up with a Rake task or removed. CI runs on Ruby 3.2, 3.3, 3.4.
- **Requirements:** E1, E2, E3, E4, E5, E6
- **First failing spec:** None — this is a config/infrastructure change. Validate
  with `bundle exec rspec` (full suite green) and `bundle exec rubocop` (no new
  offenses after version bump).
- **Likely files:**
  - `rails-ai-bridge.gemspec` — update rubocop, rubocop-rails-omakase, combustion, pry constraints
  - `Gemfile` — update pry constraint
  - `.yardopts` (new) — if keeping yard
  - `Rakefile` (new or update) — add `yard` task if keeping yard
  - `.github/workflows/` — add Ruby 3.4 to CI matrix (if CI exists)
- **Decisions:**
  - **YARD: keep or remove?** PRD leans toward keeping it and wiring up. Decide
    before starting.
  - mcp stays at `~> 0.10.0` (already latest).
- **Estimated scope:** 1 small PR, ~30 minutes

---

### Phase 2: Serializer Parity & Context Quality (Pillar A)

**PR name:** `v2-serializer-parity`

- **Target behavior:** All 5 compact serializers produce equally rich output:
  complexity-sorted models, dynamic test commands, enum display, column hints,
  migration recency flags, and richer controller output.
- **Requirements:** A1, A2, A3, A4, A5, A6
- **First failing spec:**
  - `spec/lib/rails_ai_bridge/serializers/cursor_rules_serializer_spec.rb` — add
    test: "sorts models by complexity score, not alphabetically"
  - `spec/lib/rails_ai_bridge/serializers/windsurf_serializer_spec.rb` — same
- **Likely files:**
  - `lib/rails_ai_bridge/serializers/cursor_rules_serializer.rb` — complexity
    sort, enum display, column hints (A1, A3, A4)
  - `lib/rails_ai_bridge/serializers/windsurf_serializer.rb` — complexity sort,
    column hints (A1, A4)
  - `lib/rails_ai_bridge/serializers/context_summary.rb` — add
    `top_columns(model_data, schema)` helper, `recently_migrated?(model, migrations)`
    helper (A4, A5)
  - `lib/rails_ai_bridge/serializers/claude_serializer.rb` — add column hints,
    migration recency (A4, A5)
  - `lib/rails_ai_bridge/serializers/codex_serializer.rb` — same (A4, A5)
  - `lib/rails_ai_bridge/serializers/copilot_serializer.rb` — same (A4, A5)
  - All 5 serializer specs — new tests for A4, A5, A6
- **Decisions:**
  - **Column format:** `[cols: name, email, role]` or `[cols: name:string]`?
    Decide during A4 implementation.
  - **Migration recency threshold:** 30 days hardcoded (YAGNI).
- **Dependencies:** Phase 1 (rubocop update) for clean linting.
- **Estimated scope:** 1 medium PR, ~2-3 hours

---

### Phase 3: Metz Refactoring — Serializers (Pillar B)

**PR name:** `v2-serializer-formatters`

- **Target behavior:** MarkdownSerializer is < 80 lines. Each section formatter
  is < 60 lines, independently testable. No `Metrics/MethodLength` rubocop
  disables. Serializers receive config via constructor, not global query.
- **Requirements:** B1, B2, B3, B4
- **First failing spec:**
  - `spec/lib/rails_ai_bridge/serializers/formatters/models_formatter_spec.rb` —
    test that it renders model lines given a models hash
- **Likely files:**
  - `lib/rails_ai_bridge/serializers/formatters/` (new directory):
    - `schema_formatter.rb`, `models_formatter.rb`, `routes_formatter.rb`,
      `gems_formatter.rb`, `controllers_formatter.rb`, `jobs_formatter.rb`,
      `auth_formatter.rb`, `views_formatter.rb`, `mcp_guide_formatter.rb`,
      `conventions_formatter.rb`, `migrations_formatter.rb`
  - `lib/rails_ai_bridge/serializers/markdown_serializer.rb` — slim down to
    orchestrator composing formatters
  - `lib/rails_ai_bridge/serializers/claude_serializer.rb` — constructor
    injection, compose formatters
  - `lib/rails_ai_bridge/serializers/codex_serializer.rb` — same
  - `lib/rails_ai_bridge/serializers/copilot_serializer.rb` — same
  - `lib/rails_ai_bridge/serializers/cursor_rules_serializer.rb` — same
  - `lib/rails_ai_bridge/serializers/windsurf_serializer.rb` — same
  - All existing serializer specs — update to use constructor injection
  - `spec/lib/rails_ai_bridge/serializers/formatters/` (new) — unit specs per
    formatter
- **Decisions:**
  - **Formatter interface:** `Formatter.new(context, config).call -> Array<String>`
    (returns lines, not joined string). Serializers concat lines from formatters.
  - **Full-mode composition:** Replace `FullClaudeSerializer < MarkdownSerializer`
    with `MarkdownSerializer.new(context, config, header: ..., footer: ...)`.
- **Dependencies:** Phase 2 (parity) must be done — otherwise we extract
  inconsistent code and then have to touch formatters again.
- **Estimated scope:** Largest phase. 2-3 PRs or 1 large PR. ~4-6 hours.
- **Risk:** This is a pure refactor (behavior-preserving). Existing serializer
  specs are the characterization tests. Every step must keep them green.

---

### Phase 4: Metz Refactoring — Configuration (Pillar C)

**PR name:** `v2-config-objects`

- **Target behavior:** `Configuration` is a facade (< 100 lines) delegating to
  `Config::Auth`, `Config::Introspection`, `Config::Output`, `Config::Server`.
  Public DSL (`config.http_mcp_token = "..."`) continues to work unchanged.
- **Requirements:** C1, C2, C3
- **First failing spec:**
  - `spec/lib/rails_ai_bridge/config/auth_spec.rb` — test that
    `Config::Auth.new` has sensible defaults and exposes `jwt_decoder`,
    `token_resolver`, `static_token`
- **Likely files:**
  - `lib/rails_ai_bridge/config/` (new directory):
    - `auth.rb`, `introspection.rb`, `output.rb`, `server.rb`
  - `lib/rails_ai_bridge/configuration.rb` — slim to facade with
    `delegate`/`method_missing` or explicit wrappers
  - `lib/rails_ai_bridge/mcp/authenticator.rb` — use `Config::Auth` directly
    instead of querying 3 separate config attrs
  - `spec/lib/rails_ai_bridge/config/` (new) — unit specs per config object
  - `spec/lib/rails_ai_bridge/configuration_spec.rb` — verify backward
    compatibility (existing tests must still pass)
- **Decisions:**
  - **Delegation pattern:** Explicit delegation (`def http_mcp_token = auth.static_token`)
    vs `delegate` macro vs `method_missing`. Prefer explicit — debuggable and
    YARD-friendly.
- **Dependencies:** Phase 3 (serializers use constructor injection). If serializers
  still query global config, splitting config is pointless.
- **Estimated scope:** 1 medium PR. ~2-3 hours.

---

### Phase 5: Metz Refactoring — Tools & Introspector (Pillar D)

**PR name:** `v2-tool-decomposition`

- **Target behavior:** `GetSchema.call` and `GetModelDetails.call` are < 15 lines
  each, delegating to detail-level formatters. Introspector registry
  auto-discovers introspector classes. Tool param counts <= 4.
- **Requirements:** D1, D2, D3, D4
- **First failing spec:**
  - `spec/lib/rails_ai_bridge/tools/schema/summary_formatter_spec.rb` — test
    that it formats a schema hash into summary lines
- **Likely files:**
  - `lib/rails_ai_bridge/tools/schema/` (new directory):
    - `summary_formatter.rb`, `standard_formatter.rb`, `full_formatter.rb`
  - `lib/rails_ai_bridge/tools/model_details/` (new directory):
    - `summary_formatter.rb`, `standard_formatter.rb`, `full_formatter.rb`
  - `lib/rails_ai_bridge/tools/get_schema.rb` — slim `call` method
  - `lib/rails_ai_bridge/tools/get_model_details.rb` — slim `call` method
  - `lib/rails_ai_bridge/introspector.rb` — replace hash with auto-discovery
  - `spec/lib/rails_ai_bridge/tools/schema/` and `model_details/` — new specs
  - `spec/lib/rails_ai_bridge/introspector_spec.rb` — verify auto-discovery
- **Decisions:**
  - **Introspector auto-discovery:** Glob `introspectors/*.rb` + derive class
    names via `classify`. Simpler than Zeitwerk callbacks, no coupling to loader
    internals.
  - **Params object:** Evaluate whether a `ToolParams` struct is worth it or if
    keyword args already keep counts <= 4 after extraction.
- **Dependencies:** Can run after Phase 2 (for column hints in schema formatter).
  No hard dependency on Phase 3/4.
- **Estimated scope:** 1 medium PR. ~2-3 hours.

---

### Phase 6: Coverage, CHANGELOG & Release Prep (Pillar F)

**PR name:** `v2-release-prep`

- **Target behavior:** >= 85% line coverage, CHANGELOG documents all changes,
  version is 2.0.0, all rubocop offenses resolved, YARD clean.
- **Requirements:** F1, F2, F3, F4, F5, F6
- **First failing spec:** Coverage gap analysis — run `bundle exec rspec` and
  identify files below 80% coverage from SimpleCov report.
- **Likely files:**
  - `spec/lib/rails_ai_bridge/serializers/context_file_serializer_spec.rb` — add
    split-rules spec
  - `spec/lib/rails_ai_bridge/serializers/shared_assistant_guidance_spec.rb` —
    add output verification
  - All 5 serializer specs — add end-to-end integration tests (minitest context
    through full pipeline)
  - `lib/rails_ai_bridge/version.rb` — bump to `2.0.0`
  - `CHANGELOG.md` — write complete entry
  - Any files flagged by SimpleCov as uncovered
- **Dependencies:** All previous phases complete.
- **Estimated scope:** 1 PR. ~2-3 hours.

---

## Phase Summary

| Phase | Pillar | PR name | Estimated | Key risk |
|-------|--------|---------|-----------|----------|
| 1 | E | `v2-dependencies` | 30 min | Low — infra only |
| 2 | A | `v2-serializer-parity` | 2-3h | Medium — touching 5 serializers |
| 3 | B | `v2-serializer-formatters` | 4-6h | High — largest refactor, must preserve behavior |
| 4 | C | `v2-config-objects` | 2-3h | Medium — backward compat is critical |
| 5 | D | `v2-tool-decomposition` | 2-3h | Medium — auto-discovery design choice |
| 6 | F | `v2-release-prep` | 2-3h | Low — coverage and docs |

**Total estimated:** ~13-18 hours of focused work across 6 PRs.

## Completion

After all phases:

- **YARD:** Every new/changed public class and method documented (per-phase, not batched)
- **Documentation:** CHANGELOG.md, update README if install or config workflow changed
- **Self-review:** `rails-code-review` on each PR before merge; `rails-architecture-review` on Phase 3 (serializer extraction) and Phase 4 (config split)
- **Final gate:** `rails-engine-release` skill checklist before tagging 2.0.0

## Resolved Decisions

1. **Introspector registry:** Glob + classify — simpler, no Zeitwerk coupling, testable in isolation
2. **Column hints format:** `[cols: name:string, email:string]` — types included for higher AI context density
3. **Migration recency:** 30 days hardcoded (YAGNI)
4. **YARD gem:** Keep and wire up with Rake task + `.yardopts`
