# Design: v6.0 Dependency graph introspector + `rails_get_dependency_graph`

Epic: [#265](https://github.com/igmarin/rails-ai-bridge/issues/265) — v6.0 dependency graph introspector + tool (milestone #9, phase 3).

## Problem / Motivation

Agents lack woods-style dependency knowledge: which models a controller touches, controller to
view to job/service edges, association graphs, and where callbacks mutate state. Today this is only
discoverable piecemeal by cross-reading the `:models`, `:controllers`, `:views`, and `:jobs`
sections — and nothing surfaces reverse edges ("what breaks if I change `User`?").

`woods` builds forward/reverse dependency graphs including callbacks with side effects; that is the
capability bar epic #265 targets. The bridge already holds most raw inputs: model associations
(reflection), controller filters/renders, `ViewFileAnalyzer` view references, job classes, and —
optionally — `RubydexAdapter` reference data for cross-layer edges.

## Goals / Non-goals

**Goals**

1. New introspector `:dependency_graph` producing typed forward/reverse edges with per-edge
   provenance, plus cycles (SCC) detection.
2. New tool `rails_get_dependency_graph` with entity focus, direction/kind filters, and
   `detail:` levels that respect compact-by-default.
3. Hard size caps configurable in `Config::Introspection`, with deterministic truncation.

**Non-goals**

- No runtime call-graph tracing (static extraction only; no runtime hooks).
- No visualization format (DOT/Mermaid) in v6.0 — JSON/markdown only.
- No writes, no code execution: edges are read-only derived data.
- Not a replacement for `rails_search_semantic`; complementary.

## Design

### Architecture overview

Two new files, both inside existing components (no component redefinition, no #250 edge churn):

```text
lib/rails_ai_bridge/introspectors/dependency_graph_introspector.rb   (component: introspectors)
lib/rails_ai_bridge/tools/get_dependency_graph.rb                    (component: tools)
```

The introspector reuses already-cached sections (`:models`, `:controllers`, `:views`, `:jobs`) via
`ContextProvider.fetch_section` rather than re-reflecting, and optionally `RubydexAdapter.instance`
for cross-layer references (same call pattern as `ModelSemanticEnrichment`; `rubydex` is optional and
absence must not change the graph shape, only provenance/edge counts). The tool reads the section via
`BaseTool.cached_section(:dependency_graph)` — the established tools-to-introspectors data path.

Archspec notes: `introspectors` may use `rubydex`/`runtime_context` (existing allowance); the new
edge `tools -> runtime_context (ContextProvider)` already exists. Nothing new participates in the
baselined 6-component SCC beyond edges it already classifies; `archspec_rules_spec` must stay green
with only the baselined `archspec_todo.yml` violation.

### Data model

```ruby
{
  nodes: [{ id: 'model/User', type: :model, name: 'User', path: 'app/models/user.rb' }],
  edges: [{ from: 'controller/UsersController', to: 'model/User',
            kind: :references, source: :reflection }],   # forward edges; reverse computed
  cycles: [['model/A', 'model/B']],                      # SCCs with size > 1
  stats: { node_count: 42, edge_count: 130, truncated: false,
           by_kind: { association: 60, render: 25 } }
}
```

- **Node types**: `model`, `controller`, `job`, `service` (`app/services`), `view` (components and
  notable partials, capped), `mailer`.
- **Edge kinds** (woods parity): `association`, `callback` (with `side_effect: true` when the
  callback body creates/updates/destroys/sends — detected structurally, tagged `source: :regex`
  unless Prism/rubydex confirms), `render`, `deliver`, `perform`, `references`.
- **Provenance per edge** (`source:`) keeps this forward-compatible with #264 confidence tags
  without importing anything from the tools layer.
- Reverse lookup is computed in the tool from `edges` (index `to -> [edge]`), not stored, keeping
  the cached payload smaller.

### Size limits (compact-by-default)

`Config::Introspection` gains:

| Attribute | Default | Behavior |
|---|---|---|
| `dependency_graph_max_nodes` | `400` | overflow nodes dropped lowest-degree-first (deterministic) |
| `dependency_graph_max_edges` | `1500` | overflow edges dropped in reverse-degree order |
| `dependency_graph_kinds` | all kinds | allowlist filter |

Truncation is explicit and stable: `stats[:truncated] == true` plus a `truncated_note` string; node
sort order (type, name) is deterministic so `ToolResultCache` fingerprints stay stable across calls.
`BaseTool.text_response` remains the final backstop via `max_tool_response_chars`.

### Config surface

- Sub-config: `Config::Introspection` (the three attributes above), flat delegators on
  `Configuration`.
- Preset membership (explicit): `:dependency_graph` is added to the **`:full` preset only**
  (27 -> 28). Rationale: `:full` is the power-user preset; a graph is high-value there, and caps
  bound its cost. `:standard` (9) and `:regulated` (6) stay unchanged — regulated environments
  should not gain a new cross-cutting surface implicitly.
- Category mapping: new entry `architecture: %i[dependency_graph]` in
  `INTROSPECTION_CATEGORY_INTROSPECTORS`, so `disabled_introspection_categories = [:architecture]`
  cleanly removes it for hosts that opted in.
- `selected_introspectors` already gates `only:` fetches against `effective_introspectors`, so
  `rails_get_dependency_graph` in a `:standard` host returns the standard "not available" guidance
  instead of running the introspector.

### Tool / response surface

`tool_name 'rails_get_dependency_graph'`, registered in `Server::TOOLS` as tool #23 — after
`rails_query`/`rails_read_logs` (tools #21/#22 planned by #258) to avoid colliding with that
rollout; if this lands first it takes #21 and #258 renumbers.

Parameters:

| Param | Type | Default | Notes |
|---|---|---|---|
| `entity` | string | nil | focus node (e.g. `User`, `UsersController`); restricts to its neighborhood |
| `direction` | enum `forward`/`reverse`/`both` | `both` | |
| `kind` | string | nil | edge-kind filter (`association`, `callback`, ...) |
| `depth` | integer 1-3 | `2` | neighborhood depth when `entity` is set |
| `detail` | enum `summary`/`standard`/`full` | `summary` | |
| `format` | enum `json`/`markdown` | `markdown` | |

Detail levels:

- `summary`: node/edge counts by type/kind, top hubs (highest degree), cycle count. Fits compact.
- `standard`: nodes of the requested scope plus edges touching controllers; reverse index rendered
  for the top 20 referenced nodes.
- `full`: complete edge list within caps, cycles listed; markdown tables.

Annotations: `read_only_hint: true, destructive_hint: false, idempotent_hint: true,
open_world_hint: false` — matching every existing introspection tool.

Errors follow the shared contract: section missing -> guidance message
("Add :dependency_graph to introspectors (preset :full)"); section `:error` -> forward the message;
oversized output -> truncation suffix from `text_response`.

MCP resources: **deferred.** A static `rails://dependency-graph` resource would fight
compact-by-default; the tool covers on-demand reads. Revisit with the backlog "live resource
templates" item.

## TDD plan

First failing specs (write, run, confirm red for the right reason):

1. `spec/lib/rails_ai_bridge/introspectors/dependency_graph_introspector_spec.rb`
   - `#call` returns a Hash with `:nodes`, `:edges`, `:cycles`, `:stats` keys on a fixture app.
   - An `association` edge exists from `User` to `Post` with `source: :reflection`.
   - With `dependency_graph_max_nodes: 1` configured, `stats[:truncated]` is `true` and node count
     equals 1 (deterministic survivor: highest degree).
   - Malformed fixture (edge source raising) yields `{ error: ... }` — never raises.
2. `spec/lib/rails_ai_bridge/tools/get_dependency_graph_spec.rb`
   - `tool_name == 'rails_get_dependency_graph'`; annotations include
     `destructive_hint: false`, `read_only_hint: true`.
   - Without the section cached, returns the "not available" guidance naming the `:full` preset.
   - `entity: 'User', direction: 'reverse'` lists controllers referencing `User`.
3. `spec/lib/rails_ai_bridge/tools/get_dependency_graph_detail_spec.rb`
   - `summary` output length < `full` output length; `summary` contains counts but no edge table;
     `full` contains a cycles section when the fixture has a cycle.
4. `spec/lib/rails_ai_bridge/configuration_spec.rb` (extend) — `:full` preset includes
   `:dependency_graph`; `:standard` and `:regulated` do not; `INTROSPECTION_CATEGORY_INTROSPECTORS`
   maps `:architecture` to it.

Implementation order: (1) introspector + caps + provenance -> (2) preset/category wiring ->
(3) tool with detail formatters -> (4) register in `Server::TOOLS` -> (5) parity counts
(22 -> 23 post-#258) -> (6) docs.

## Risks / mitigations

- **Payload size**: caps + deterministic truncation + `max_tool_response_chars` backstop; `summary`
  default keeps agents from pulling the full graph by accident.
- **Perf**: graph built from already-cached sections; SCC via standard algorithm bounded by
  `max_nodes`; runs lazily only when requested; `parallel_timeout_seconds` still applies.
- **Wrong edges from regex**: every heuristic edge carries `source: :regex`; #264 will upgrade these
  without changing consumers.
- **Zeitwerk**: class name `DependencyGraphIntrospector` under `introspectors/` is conventional and
  autoloads; the tool class name matches its file.
- **Backwards compat**: additive introspector key; hosts on `:standard` see zero change; JSON
  consumers gain a new section key only.
- **Cache stability**: deterministic ordering keeps `ToolResultCache` fingerprints meaningful;
  graph payload participates in the existing full-snapshot fingerprint invalidation.

## Rollout

- Milestone #9 items: design doc (this), then implementation sub-issue, tool registration, parity
  specs green (epic acceptance criteria).
- Tool numbering: after #258 lands `rails_query`/`rails_read_logs` (#21/#22), this registers as
  #23; if it lands first, it takes #21 and #258 renumbers — coordination noted in both epics.
- Doc parity updates: README tool count/table row, `server.json` tools list + description count,
  GUIDE "Dependency graph" section, `docs/ROADMAP.md` phase-3 status, CHANGELOG 6.0.0,
  AGENTS.md tool-count notes if any.
- Deprecation/compat: none; purely additive.

## Alternatives considered

- **Compute the graph inside the tool from multiple sections** (no introspector): rejected —
  uncacheable, invisible to `effective_introspectors` gating, untestable via the parity pattern,
  and it would duplicate filtering logic.
- **Store a reverse index in the payload**: rejected — doubles cached size; reverse lookup is
  trivial at tool time.
- **Rubydex-only graph**: rejected — rubydex is optional; the feature must exist without it.
- **Separate `rails_get_reverse_deps` tool**: rejected — `direction:` param is smaller surface and
  one tool keeps the count compact.

## Open questions

1. Should `service` nodes include `app/models` POROs (non-AR classes from `:non_ar_models`) when
   that introspector is enabled, or stay limited to `app/services`?
2. Default `depth` for entity focus: `2` proposed — is `1` safer for compact responses given
   controllers with many associations?
3. Do cycles include self-edges (a model referencing itself) in the `cycles` list, or only SCCs of
   size > 1?
