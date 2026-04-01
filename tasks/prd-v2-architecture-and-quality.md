# PRD: rails-ai-bridge v2.0.0 — Architecture, Quality & Gem Maturity

## Introduction/Overview

rails-ai-bridge v1.1.0 delivers working introspection and MCP tooling, but code
reviews and a Sandi Metz analysis exposed structural debt that will compound as
the gem grows: a 505-line god-class serializer, a 191-line configuration object
with 34 attributes, inconsistent serializer coverage across AI assistants, and
dependency constraints that will lag behind ecosystem releases.

This PRD defines what v2.0.0 must accomplish to make the gem a solid,
maintainable foundation — one where adding a new AI assistant or introspector is
a small, predictable change instead of a cross-cutting edit.

The current branch `pr5-context-quality` (11 commits: security exclusions,
flexible MCP auth, production safety, install UX, context quality, Authenticator
service object) is the starting base. This PRD scopes the **remaining work**
needed before tagging 2.0.0.

## Goals

- Every serializer (Claude, Codex, Copilot, Cursor, Windsurf) produces equally
  high-quality compact context — complexity-sorted models, dynamic test commands,
  enum display, schema column hints.
- No class exceeds 100 lines (Metz limit). God classes are decomposed into
  focused, composable objects.
- Configuration is grouped into focused value objects (auth, introspection,
  output, server) — each independently testable.
- Dependencies injected at construction, not queried from global singletons at
  call time.
- Gemspec dependencies are current and forward-compatible: Ruby >= 3.2 with
  CI-verified 3.4 support, mcp gem at latest stable.
- Test coverage >= 85% line coverage; zero failures across the full matrix.
- YARD docs on every public class and method.

## User Stories

1. **As a gem consumer using Cursor**, I want compact context that surfaces my
   most complex models first (not alphabetically) so the AI understands my domain
   without me manually curating rules files.

2. **As a gem consumer using Windsurf**, I want the test command in my rules file
   to match my actual framework (minitest or rspec) so I don't get wrong
   instructions.

3. **As a gem contributor**, I want to add a new AI assistant serializer by
   creating a small, focused class (~50 lines) that composes shared formatters,
   not by copy-pasting 200+ lines from ClaudeSerializer.

4. **As a gem contributor**, I want to add a new introspector without editing a
   26-entry hash in introspector.rb — the registry should be open for extension.

5. **As a gem maintainer**, I want `bundle update` to pick up mcp SDK patches
   without manual constraint edits, and I want CI green on Ruby 3.2, 3.3, and
   3.4.

6. **As a gem consumer**, I want compact model output to include the 2-3 most
   important columns (primary key, foreign keys, timestamps excluded) so the AI
   knows what data each model holds at a glance.

## Functional Requirements

### Pillar A: Serializer Parity & Context Quality

- **A1.** Cursor and Windsurf serializers must sort models by complexity score
  (same formula as Claude/Codex/Copilot: associations + validations + callbacks +
  scopes).
- **A2.** Cursor and Windsurf serializers must use
  `ContextSummary.test_command(context)` instead of hardcoded `bundle exec
  rspec`.
- **A3.** Cursor serializer must display enum names inline in model lines (same
  format as Claude: `[enums: status, priority]`).
- **A4.** All compact serializers must include top-3 non-housekeeping columns
  (exclude `id`, `created_at`, `updated_at`, `*_id` foreign keys) per key model
  when schema data is available.
- **A5.** All compact serializers must flag models whose migration was applied
  within the last 30 days (e.g., `[recently migrated]`) when migration
  timestamps are available in context.
- **A6.** Compact controller output must include action names and their HTTP
  verbs, not just controller count.

### Pillar B: Metz Refactoring — Serializers

- **B1.** Extract `MarkdownSerializer` (505 lines, 30 methods) into composable
  section formatters. Each formatter handles one concern (schema, models, routes,
  gems, etc.) and is independently testable. Target: no formatter > 60 lines,
  MarkdownSerializer orchestrator < 80 lines.
- **B2.** Replace `FullClaudeSerializer`, `FullCodexSerializer`,
  `FullCopilotSerializer` inheritance with composition — pass header/footer
  blocks or templates to MarkdownSerializer instead of subclassing.
- **B3.** Serializers must receive configuration via constructor injection (mode,
  limits, context) — not query `RailsAiBridge.configuration` at call time.
- **B4.** `render_mcp_guide` (47 lines) must be extracted to its own formatter
  with rubocop-clean methods (no `Metrics/MethodLength` disables).

### Pillar C: Metz Refactoring — Configuration

- **C1.** Split `Configuration` (191 lines, 34 attrs) into focused config
  objects: `Config::Auth`, `Config::Introspection`, `Config::Output`,
  `Config::Server`. The top-level `Configuration` delegates to these.
- **C2.** Each config object must be independently instantiable and testable
  (constructor with keyword args and sensible defaults).
- **C3.** `Config::Auth` must encapsulate the 3-strategy priority chain
  currently duplicated between `Authenticator.resolve_strategy` and the
  initializer template documentation.

### Pillar D: Metz Refactoring — Tools & Introspector

- **D1.** `GetSchema.call` (64 lines, 5 params) must be decomposed: extract
  detail-level formatters (SummaryFormatter, StandardFormatter, FullFormatter)
  invoked by a < 15-line `call` method.
- **D2.** `GetModelDetails.call` (52 lines) must follow the same pattern.
- **D3.** Replace the 26-entry `BUILTIN_INTROSPECTORS` hash with an
  auto-discovery registry (e.g., scan `introspectors/` directory or use
  `Zeitwerk` callbacks). Adding a new introspector must not require editing the
  hash.
- **D4.** Reduce tool parameter counts to <= 4. Use a params object or keyword
  pattern where needed.

### Pillar E: Dependency & Compatibility

- **E1.** Update `mcp` constraint to `~> 0.10.0` (already current — 0.10.0 is
  the latest stable release as of March 2026). Pin to pessimistic minor to
  accept patches.
- **E2.** Update `rubocop` to `~> 1.75` or later; update
  `rubocop-rails-omakase` to `~> 1.1`.
- **E3.** Update `combustion` to `~> 1.5`, `pry` to `~> 0.15`.
- **E4.** Decide on `yard` gem: either add a `rake yard` task and `.yardopts`
  file, or remove the dependency. No dead weight.
- **E5.** Maintain `required_ruby_version >= 3.2.0`. Add Ruby 3.4 to CI matrix.
  Do NOT bump minimum to 3.4 — keep 3.2 as floor.
- **E6.** Verify all runtime dependencies are compatible with Ruby 3.4. Document
  any known issues.

### Pillar F: Test Coverage & Release Prep

- **F1.** Achieve >= 85% line coverage (currently 81.55%).
- **F2.** Add missing unit specs: `ExclusionHelper` edge cases (already started),
  `ContextFileSerializer` split rules, `SharedAssistantGuidance` output.
- **F3.** Add integration specs for each serializer verifying end-to-end: minitest
  context flows through complexity sort, dynamic test command, enum display, and
  column hints.
- **F4.** Version bump to `2.0.0` in `version.rb`.
- **F5.** Write `CHANGELOG.md` entry covering all 5 original PRs plus the
  refactoring pillars.
- **F6.** Run `rails-engine-release` skill checklist before tagging.

## Non-Goals (Out of Scope)

- **No Ruby 4.0 minimum** — too early. Keep >= 3.2, test 3.4, note 4.0 when
  it ships.
- **No new introspectors** — v2.0.0 refactors existing ones, doesn't add new
  categories.
- **No new serializers** — parity across existing 5 assistants, not new ones.
- **No runtime performance optimization** — the bottleneck is host-app boot,
  not introspection. Premature optimization is out of scope.
- **No breaking changes to the public `RailsAiBridge.configuration` DSL** —
  users must be able to upgrade from 1.1.0 without rewriting their initializer.
  New config objects are internal; the top-level DSL delegates to them.
- **No MCP SDK fork or monkey-patching** — work within the official mcp gem API.
- **No RubyGems release** — release process is tracked separately via
  `rails-engine-release` skill and is not part of this PRD.

## Technical Considerations

- **Backward compatibility:** The `config.http_mcp_token = "..."` DSL must keep
  working. `Configuration` becomes a facade that delegates to `Config::Auth`,
  `Config::Introspection`, etc. Existing `attr_accessor` names stay the same.
- **Zeitwerk and auto-discovery:** The introspector registry (D3) can leverage
  `Zeitwerk::Loader#on_load` callbacks or simply glob `introspectors/*.rb` and
  derive class names. Choose the simpler approach.
- **mcp gem stability:** 0.10.0 is the latest. The API changed significantly
  between 0.8 and 0.10 (constructor-only resources). Expect possible future
  changes — keep the MCP integration surface small (server.rb, resources.rb,
  tools/).
- **Reference gem:** `../rails-ai-context` uses mcp ~> 0.8 and has a simpler
  architecture. Useful for cross-referencing MCP patterns but not a design
  target.

## Implementation Surface

- `lib/rails_ai_bridge/serializers/` — section formatters extraction (B1-B4),
  parity fixes (A1-A6)
- `lib/rails_ai_bridge/serializers/formatters/` — new directory for extracted
  section formatters
- `lib/rails_ai_bridge/configuration.rb` — facade refactoring (C1-C3)
- `lib/rails_ai_bridge/config/` — new directory for focused config objects
- `lib/rails_ai_bridge/tools/` — method decomposition (D1-D2)
- `lib/rails_ai_bridge/introspector.rb` — registry refactoring (D3)
- `rails-ai-bridge.gemspec` — dependency updates (E1-E4)
- `Gemfile` — dev dependency updates (E3)
- `spec/` — coverage improvements (F1-F3)
- `CHANGELOG.md` — release notes (F5)
- `lib/rails_ai_bridge/version.rb` — bump to 2.0.0 (F4)

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Longest class (lines) | 505 (MarkdownSerializer) | < 100 |
| Configuration attrs in one class | 34 | < 12 per config object |
| Test coverage | 81.55% | >= 85% |
| Serializers with complexity sort | 3/5 | 5/5 |
| Serializers with dynamic test cmd | 3/5 | 5/5 |
| rubocop Metrics/MethodLength disables | >= 1 | 0 |
| Dead dev dependencies | 1 (yard unused) | 0 |
| Ruby versions in CI | 3.2, 3.3 | 3.2, 3.3, 3.4 |

## Open Questions

1. **Introspector registry: Zeitwerk callback vs glob?** Zeitwerk `on_load` is
   elegant but couples to the autoloader. Glob + `const_get` is simpler and
   explicit. Decide during D3 implementation.
2. **Column hints format:** Should compact output show column names only
   (`[cols: name, email, role]`) or include types (`[cols: name:string,
   email:string, role:integer]`)? Decide during A4 implementation.
3. **Migration recency source:** `context[:migrations]` has timestamps. Is 30
   days the right threshold, or should it be configurable? Lean toward
   hardcoded 30 days (YAGNI) but flag for user feedback.
4. **yard gem decision:** Keep and wire up, or remove? The codebase has
   extensive YARD annotations already. Adding a Rake task is ~10 lines. Leaning
   toward keeping it and wiring it up.
