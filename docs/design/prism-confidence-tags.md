# Design: v6.0 Prism confidence tags (`[VERIFIED]` / `[INFERRED]`)

Epic: [#264](https://github.com/igmarin/rails-ai-bridge/issues/264) — v6.0 Prism confidence tags (milestone #9, phase 3).

## Problem / Motivation

Runtime reflection is authoritative but incomplete: before boot, or for facts ActiveRecord never
exposes (source macros, regex-extracted scopes), the bridge falls back to static heuristics whose
results may be wrong. Agents currently have no way to tell which returned facts are runtime-verified
versus inferred, except on two tools: `rails_get_schema` and `rails_get_model_details` (since #187)
already tag facts via `Tools::ConfidenceTag`.

`rails-ai-context` addresses this gap with confidence tags backed by a Prism AST pass
(`[VERIFIED]` for AST-provable structure, `[INFERRED]` for heuristics) and is a direct competitive
pressure point. Epic #264 asks for: an optional Prism static pass alongside runtime reflection, and
confidence tags carried by every tool response section, telling agents what still needs a runtime
check. The related backlog item "static tier + `[STATIC]` tags" pairs with this design but is out of
scope here.

Existing building blocks:

- `lib/rails_ai_bridge/tools/confidence_tag.rb` — `ConfidenceTag.for(source)` maps
  `%i[reflection rubydex prism live]` to `[VERIFIED]`, everything else to `[INFERRED]`.
- `RubydexAdapter` (optional gem) already indexes the app with Prism-based analysis and feeds
  `ModelSemanticEnrichment`.
- `StaticApp.STATIC_CAPABLE` / `BOOT_REQUIRED` capability split for no-boot operation.

## Goals / Non-goals

**Goals**

1. Formalize the tag vocabulary and make it available to **every** MCP tool response section, not
   just schema and models.
2. Add an optional Prism static pass that upgrades heuristic facts to AST-provable facts where
   possible, off by default, degrading silently when Prism is unavailable.
3. Keep introspectors emitting plain data: provenance travels in introspector payloads; only the
   tools layer renders tags.
4. Stay compact-by-default: tags must not inflate summaries.

**Non-goals**

- No new MCP tool (the tag system is orthogonal to tool count; parity counts unchanged).
- No `[STATIC]` full static tier (backlog item; reserved token only).
- No LLM-based confidence scoring.
- No behavior change when `confidence_tags` are disabled.

## Design

### Architecture overview

Layering follows `Archspec.rb` components; introspectors stay free of tools/serializers/mcp_transport.

```text
Config::StaticAnalysis (config)          new sub-config, leaf layer
        | settings only
Introspectors::*  --emit provenance-->  payloads gain `provenance:` symbols
Introspectors::StaticPrismScanner        new; Prism AST facts per file, fingerprint-cached
        | (uses Prism + RubydexAdapter only when enabled)
Tools::*          --render------------>  ConfidenceTag footer + inline tags (tools layer)
```

**Provenance flows up, tags render in tools.** Introspectors attach a `provenance:` symbol per fact
(`:reflection`, `:rubydex`, `:prism`, `:regex`, `:heuristic`). `ConfidenceTag.for` maps them. This
avoids any new cross-component edge and does **not** touch the #250 situation: the baselined
6-component SCC (`archspec_todo.yml`, issue #250) is untouched because we add no file moves and no
new edges — `StaticPrismScanner` lives in `introspectors/` (glob-covered), reads files, and never
imports tools. `RubydexAdapter` use from introspectors is the existing pattern (`ModelSemanticEnrichment`).

**Which introspectors get tags first** (epic requirement): schema and models are done (#187). Order
of the remaining rollout: controllers (before_action filters and strong params are regex-derived
today, so `[INFERRED]`, upgraded to `[VERIFIED]` when Prism proves the filter method exists), then
jobs (sidekiq/activejob class-level config), then views. Routes are runtime-extracted and stay
implicitly `[VERIFIED]`.

### Prism scanner

`Introspectors::StaticPrismScanner`:

- Soft-requires Prism (bundled default gem on Ruby >= 3.3; added as an optional gem dependency for
  3.2, same `available?` rescue pattern as `RubydexAdapter`).
- Parses `app/{models,controllers,jobs}/**/*.rb` respecting `max_files_per_path` and
  `excluded_paths`; emits per-class facts: method definitions, constant references, callback
  registrations. Structural facts only — Prism proves syntax/shape, never runtime semantics.
- Results are memoized per file and invalidated by `Fingerprinter` fingerprints, so tool calls pay
  parse cost once per source change.
- Never raises: malformed source yields `{ error: 'parse failed: <file>' }` entries per the
  introspector error contract.

### Tag vocabulary

| Tag | Meaning | Sources |
|---|---|---|
| `[VERIFIED]` | Provable at runtime or via AST | `reflection`, `rubydex`, `prism`, `live` |
| `[INFERRED]` | Regex/heuristic or absent provenance | `regex`, `heuristic`, `nil` |
| `[STATIC]` | Reserved — static-tier fallback | backlog, not emitted in v6.0 |

Rendering rules (compact-by-default):

- Inline tags only on facts that are *not* uniformly verified: an all-`[VERIFIED]` section renders
  one footer line `Verification: associations [VERIFIED] · source macros [INFERRED]` instead of
  per-fact noise.
- JSON `format:` responses gain an additive `provenance:` key per fact; markdown rendering maps it
  to tags. Existing JSON consumers see new keys only — additive, non-breaking.
- `summary` detail level renders at most the footer line; `standard`/`full` may inline.

### Data model

Introspector payloads stay backward compatible; provenance is additive:

```ruby
# e.g. context[:controllers][:controllers]["UsersController"][:before_actions]
[{ filter: 'authenticate_user!', provenance: :regex, prism_verified: true }, ...]
```

`ConfidenceTag` gains one public helper: `ConfidenceTag.footer(provenance_counts)` returning a
markdown line. Tag strings themselves are unchanged constants.

### Config surface

New sub-config `Config::StaticAnalysis` (Configuration gains `attr_reader :static_analysis` plus
flat delegators), keeping `Config::Rubydex` scoped to rubydex only:

| Attribute | Default | Notes |
|---|---|---|
| `confidence_tags_enabled` | `true` | off = tools render exactly as today |
| `prism_enabled` | `false` | opt-in static pass; requires Prism |
| `prism_tag_sources` | `%i[reflection rubydex prism live]` | allowlist of `[VERIFIED]` sources |
| `prism_max_files` | `500` | parse cap per introspection run |

Archspec: `config/*.rb` stays a leaf (`config.cannot_use ...` untouched). No edits to component
directions; no file moves (no #250-style churn).

### Tool / response surface

- No new tools. `Server::TOOLS` unchanged; count parity specs unchanged.
- `rails_get_schema`, `rails_get_model_details` keep current behavior (already tagged).
- `rails_get_controllers`, `rails_get_test_info`, `rails_get_view` gain footer/inline tags when
  `confidence_tags_enabled`; all keep `detail:` (`summary`/`standard`/`full`), `format:`
  (`json`/`markdown`), and annotations `read_only_hint: true, destructive_hint: false,
  idempotent_hint: true, open_world_hint: false`.
- Errors unchanged: unavailable sections return the existing "not available" message, never a tag.

**Preset decision (explicit):** no preset changes. Tags ride existing introspectors; the optional
`:static_analysis` introspector is **opt-in only** (host registers via
`config.additional_introspectors` or sets `prism_enabled` to enrich existing sections). Rationale:
`[INFERRED]`-heavy output should never surprise `:standard`/`:regulated` users who never asked for
static analysis.

## TDD plan

First failing specs (write, run, confirm they fail for the right reason):

1. `spec/lib/rails_ai_bridge/tools/confidence_tag_spec.rb` — extend:
   `ConfidenceTag.footer(reflection: 3, regex: 2)` returns
   `"Verification: [VERIFIED] reflection (3) · [INFERRED] regex (2)"`; `footer({})` returns `nil`.
2. `spec/lib/rails_ai_bridge/config/static_analysis_spec.rb` — defaults:
   `confidence_tags_enabled == true`, `prism_enabled == false`, `prism_max_files == 500`; flat
   delegators reachable from `RailsAiBridge.configuration`.
3. `spec/lib/rails_ai_bridge/introspectors/static_prism_scanner_spec.rb` — with Prism stubbed
   unavailable: `#facts_for(path)` returns `{ error: '...' }`, never raises; with a fixture class,
   emits `provenance: :prism` facts capped by `prism_max_files`.
4. `spec/lib/rails_ai_bridge/tools/get_controllers_detail_spec.rb` — extend: markdown contains
   `[INFERRED]` for regex-derived filters when `prism_enabled=false`; `[VERIFIED]` on the same fact
   when the scanner marks `prism_verified: true`; absent entirely when
   `confidence_tags_enabled=false`.

Implementation order: (1) `ConfidenceTag.footer` -> (2) `Config::StaticAnalysis` + delegators ->
(3) `StaticPrismScanner` (prism-optional, error-safe) -> (4) provenance on controller introspector ->
(5) tool rendering (controllers first, then jobs, views) -> (6) docs parity.

## Risks / mitigations

- **False `[VERIFIED]`**: Prism proves structure, not behavior. Mitigation: `prism_tag_sources`
  allowlist; only structural facts (method/constant/callback existence) may be verified.
- **Perf**: AST parsing large trees. Mitigation: opt-in default-off, `prism_max_files` cap,
  fingerprint-gated memoization, lazy per-section runs via `ContextProvider.fetch_section`.
- **Prism availability on Ruby 3.2**: soft require with `available?`; degrade to `[INFERRED]`-only.
- **Zeitwerk**: `StaticPrismScanner` under `lib/rails_ai_bridge/introspectors/` autoloads cleanly;
  no nested-module surprises.
- **Archspec/#250 interplay**: zero file moves, zero new component edges; `archspec_rules_spec`
  "real gem zero violations" (modulo the baselined todo) must stay green.
- **Payload size**: footer + selective inline tags keep `summary` responses flat; JSON gains keys
  only when provenance exists.

## Rollout

- Milestone #9 (phase 3, v6.0). Implementation sub-issues created from this doc per epic #264.
- CHANGELOG 6.0.0 entry; README tool-table note ("confidence tags legend"); GUIDE section
  "Reading confidence tags"; `docs/ROADMAP.md` backlog `[STATIC]` item stays reserved.
- Deprecation/compat: none — additive keys and opt-in behavior; disabled path is byte-identical to
  today's output.
- Doc parity: README, GUIDE, CHANGELOG, ROADMAP phase-3 status flip when implementation lands.

## Alternatives considered

- **Move `ConfidenceTag` to `runtime_context`** so introspectors could tag directly: rejected —
  file move churn against the #250 baseline for no functional gain; provenance-up/tags-in-tools is
  cleaner.
- **Rubydex-only enrichment** (no raw Prism): rejected — rubydex is a heavier optional dep and not
  bundled; Prism is a default gem on 3.3+.
- **Always-on Prism**: rejected — parse cost on every introspection conflicts with
  compact-by-default and boot-time zero-config goals.
- **Tags rendered inside introspectors**: rejected — would make introspectors depend on
  presentation and break the "plain Hashes" rule (`introspectors.cannot_use :serializers, :tools`).

## Open questions

1. Should `prism_verified` be a boolean per fact, or should provenance be a single symbol per fact
   with an ordered precedence (`reflection > prism > rubydex > regex`)? Affects JSON payload shape
   consumers may rely on.
2. Do we add `gem 'prism'` unconditionally to the gemspec (harmless on 3.3+, enables 3.2) or
   document it as an optional user dependency?
3. For the reserved `[STATIC]` tag: emit it in static mode today as `environment: 'static'` implies,
   or strictly hold it for the backlog static-tier epic?
