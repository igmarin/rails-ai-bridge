# Design: v6.0 Multi-project support (`switch_project`)

Epic: [#266](https://github.com/igmarin/rails-ai-bridge/issues/266) — v6.0 multi-project / switch_project (milestone #9, phase 3).

## Problem / Motivation

`rails-ai-bridge` is single-project: one booted app per MCP server process, one config. The core
draw of `rails-mcp-server` (~259k downloads) is serving multiple Rails apps from one server with
project switching, plus version-manager-aware booting (mise/asdf/rbenv/rvm shims derived from
`.ruby-version` / `.tool-versions`). Teams working across several apps want the same without
spawning one server per project.

Single-process multi-boot is not an option: two booted Rails apps share `$LOAD_PATH`, top-level
constants, and Zeitwerk-registered autoloaders, so a second `Bundler.require`/boot in-process is
unsafe. The design therefore isolates booted projects into child processes and keeps the parent
server as a thin, project-aware proxy — while the existing `StaticApp` fast path continues to serve
static-capable sections without any boot.

## Goals / Non-goals

**Goals**

1. `rails_switch_project` MCP tool switching the active project for the calling session.
2. Project registry + per-project config overrides via a new `Config::Projects` sub-config.
3. Version-manager-aware booting of the active project (mise/asdf/rbenv/rvm detection).
4. Per-project isolation for caches, fingerprints, and context output.

**Non-goals**

- Booting two projects in one process (unsafe, rejected — see Alternatives).
- Multi-project for the Rails Engine auto-mount path (`Middleware`/`Engine`): the host app *is* the
  project. Multi-project applies to standalone server mode (stdio / standalone HTTP).
- Generating context files for projects not in the allowlist.

## Design

### Architecture overview

```text
MCP client -> parent Server (mcp_transport)
                | ProjectRegistry  (runtime_context)  -- allowlist, stable app objects, slugs
                | ProjectManager   (runtime_context)  -- active project per session/thread
                | VersionManagerResolver (runtime_context) -- shim detection, argv building
                | ChildBridge      (runtime_context)  -- one booted child per active project
                v
             child process: rails-ai-bridge server bound to that project (in-process caches)
```

- **Parent** keeps `ProjectRegistry`: one memoized `StaticApp` per allowed root (identity
  stability matters — `Fingerprinter::CachedSnapshot` keys by `app.object_id`).
- **Static fast path**: for `StaticApp.STATIC_CAPABLE` sections (schema, gems, tests, migrations,
  conventions), the parent answers directly from the target project's `StaticApp` — switching is
  instant and boot-free.
- **Boot-required sections** of the active project are served from the child process, which is a
  full rails-ai-bridge server speaking MCP stdio, spawned lazily and killed after
  `boot_timeout_seconds` of inactivity.
- `AppScope.with_app` (existing thread-local seam) scopes every tool call and resource read to the
  active project's app object; HTTP mode sets the scope per request in the existing Rack layer, so
  concurrent sessions can hold different active projects without global leakage.

### New tool: `rails_switch_project`

- **Read-only guarantee scope**: AGENTS.md's "read-only tools only" convention guards the **host
  application** (no DB writes, no DDL, no shell). `rails_switch_project` honors that: it mutates
  *server session routing state only* — which project subsequent tool calls target — and never
  touches host state. Annotations: `destructive_hint: false, read_only_hint: false,
  idempotent_hint: true` (switching to the same project is a no-op), `open_world_hint: true` (it
  reaches outside the current process). The annotation deviation from other tools is deliberate and
  surfaced for review (Open question 4): an alternative is transport-level session control outside
  the tool surface, which would forfeit the discoverability an MCP tool gives clients.
- Registered in `Server::TOOLS`; excluded from `ToolResultCache` via
  `ToolResultCache::NON_CACHEABLE` (same treatment as `rails_get_provider_context`), since its
  effect is server state.
- Returns `MCP::Tool::Response` per SDK convention; a degraded project (child crashed, boot
  timeout) yields an error message in the response body — the parent never raises through.
- Param `project` (string slug). Response: confirmation + the project's section availability
  (static-capable now vs boot-required after child boot) + context freshness fingerprint.
- Unknown slug: error message listing available slugs (mirrors `model_not_found_message` style).
- `Server::TOOLS` ordering: registered after #258's `rails_query`/`rails_read_logs` (#21/#22) and
  #265's `rails_get_dependency_graph` (#23) -> tool #24; coordination identical to the dependency
  graph doc.

### Config schema (new `Config::Projects` sub-config)

| Attribute | Default | Notes |
|---|---|---|
| `enabled` | `false` | **opt-in**; false = today's single-project behavior, byte-identical |
| `roots` | `[]` | allowlist of absolute project paths; the security boundary |
| `projects_file` | `nil` | optional YAML manifest (rails-mcp-server `projects.yml` analog) |
| `default_project` | `nil` | slug; nil = first allowlisted root |
| `max_projects` | `8` | hard cap on registered projects |
| `boot_timeout_seconds` | `60` | child boot kill switch |
| `version_manager` | `:auto` | one of `:auto, :mise, :asdf, :rbenv, :rvm, :none` |
| `per_project` | `{}` | slug -> override hash (subset: `cache_ttl`, `max_tool_response_chars`, `introspectors` preset) |

`Configuration` gains `attr_reader :projects` plus flat delegators for the common attributes.
Slugs are the project directory basename, validated against `/\A[a-z0-9_-]+\z/i`. `projects_file`
entries must resolve inside `roots` (allowlist wins over manifest).

Archspec: new files `config/projects.rb` (component `config`), `project_registry.rb`,
`project_manager.rb`, `version_manager_resolver.rb`, `child_bridge.rb` under
`lib/rails_ai_bridge/` (component `runtime_context` — added to its `in:` list in `Archspec.rb`),
`tools/switch_project.rb` (component `tools`). The parent server spawns children — an action, not a
require-direction change, so no new `cannot_use` edges and no growth of the #250 SCC; the Archspec.rb
edit (glob list) ships with the implementation PR.

### Per-project fingerprint cache isolation

- `ContextProvider.cache_key` is already `"{app.class.name}:{root}:{env}"` — distinct roots get
  distinct cache entries today; multi-project inherits isolation for free. Residual gaps to fix in
  implementation: (a) booted apps share `class.name` only if their app classes differ (they do, per
  child process — moot); (b) `Rails.env` in the parent refers to the parent process, so cache keys
  for `StaticApp`s use the parent env — acceptable, documented.
- `Fingerprinter::CachedSnapshot` keys by `app.object_id`: `ProjectRegistry` memoizes one
  `StaticApp` per project so snapshot caches stay warm across switches (identity, not re-hash).
- `ToolResultCache` fingerprints derive from the app the tool ran against — child processes cache
  independently; the parent only caches static-path results keyed by the scoped app.
- TTLs remain global config (`cache_ttl`, `snapshot_ttl`); `per_project` overrides `cache_ttl` only
  (see Open question 2).

### Security (project isolation + boot risks)

Booting a project executes its code; treat everything under an unlisted or listed root as untrusted
input — same posture `Registry::EndpointPolicy` applies to provider endpoints.

- **Allowlist only**: `roots` is mandatory when `enabled`; symlinks resolving outside a declared
  root are rejected at registration (`File.realpath` check); slugs cannot escape (`..` impossible by
  regex).
- **Untrusted project metadata**: `projects_file`, `.ruby-version`, `.tool-versions`, `mise.toml`
  are parsed read-only, never evaluated; `projects_file` uses `YAML.safe_load` with a limited
  `permitted_classes` set; version/tool values pass a strict allowlist regex
  (`/\A[a-z0-9._-]+\z/i`) before becoming argv elements; values feed fixed argv (no shell string,
  no interpolation into `system`-style calls). The resolver emits
  `['mise', 'exec', '--', 'bundle', 'exec', ...]`-style argv arrays.
- **Child process hygiene**: children inherit a **minimal env** (PATH, HOME, GEM_HOME/RBENV-*
  as resolved by the shim layer) — parent secrets are not propagated; child stdout/stderr are
  captured and redacted through `MessageSanitizer` before anything reaches the client; every spawn
  is logged at info level with project slug + argv shape (no secret values).
- **Boot discipline**: `boot_timeout_seconds` kill; `max_projects` bounds resource use; a crashing
  child marks the project degraded and returns `{ error: ... }`-shaped messaging in the tool
  response rather than crashing the parent.
- **HTTP transport**: when multi-project is enabled over HTTP, `config.mcp.require_http_auth` must
  be true (fail-closed at boot otherwise); rate-limiter keys gain the project slug prefix so one
  project cannot exhaust another's budget. Context-file generation stays rooted inside each
  project's own `output_dir_for` (writes never escape the allowlisted root).

## TDD plan

First failing specs (write, run, confirm red for the right reason):

1. `spec/lib/rails_ai_bridge/config/projects_spec.rb`
   - defaults: `enabled == false`, `roots == []`, `max_projects == 8`, `version_manager == :auto`.
   - registering a root outside `roots` raises `ConfigurationError`; symlink escaping the root is
     rejected; slug derivation and slug regex validation.
   - `projects_file` entries outside `roots` are ignored (allowlist wins).
2. `spec/lib/rails_ai_bridge/tools/switch_project_spec.rb`
   - `tool_name == 'rails_switch_project'`; annotations `destructive_hint: false`,
     `read_only_hint: false`; class is in `ToolResultCache::NON_CACHEABLE`.
   - unknown project returns a message listing available slugs (no raise).
   - switching scopes subsequent `AppScope.current_app` within the call to the project's
     memoized `StaticApp`; same-object identity across two switches (registry memoization).
   - with `enabled == false`, the tool is not registered / returns the single-project guidance.
3. `spec/lib/rails_ai_bridge/project_registry_spec.rb`
   - stable identity (same StaticApp instance per root across fetches); `max_projects` cap enforced;
     realpath escape rejected.
4. `spec/lib/rails_ai_bridge/version_manager_resolver_spec.rb`
   - precedence `.tool-versions` > `.ruby-version` for version pinning; emits argv arrays
     (`no shell string`), raises nothing when no manager found and `:none` passthrough is used.

Implementation order: (1) `Config::Projects` + validation -> (2) `ProjectRegistry` (StaticApp
memoization, allowlist) -> (3) `rails_switch_project` tool + AppScope wiring + NON_CACHEABLE ->
(4) `VersionManagerResolver` -> (5) `ChildBridge` spawn/kill/timeout -> (6) HTTP per-request
scoping + auth fail-closed -> (7) docs/parity.

## Risks / mitigations

- **Zeitwerk / multi-boot unsafety**: eliminated by design — at most one booted app per process;
  children are the isolation boundary.
- **Memory footprint**: one child per active project, killed on timeout; `max_projects` caps
  registry size; static fast path avoids boots for read-only sections.
- **Boot latency**: lazy spawn on first boot-required call; static sections never wait for boot.
- **Security — code execution by design**: opt-in `enabled=false` default, roots allowlist, minimal
  env, argv-only shim invocation, spawn logging, HTTP auth fail-closed. Documented in
  `docs/mcp-security.md` (parity update below).
- **Backwards compat**: default config keeps single-project behavior; `Server::TOOLS` gains the
  tool only when `projects.enabled` (registered dynamically alongside `additional_tools`).
- **Cache cross-talk**: covered by existing root-keyed `ContextProvider` + memoized app identity;
  spec 2 asserts identity, spec 1 asserts isolation boundaries.
- **CI/Windows**: child-spawn paths guarded; resolver is pure file reading (spec 4 runs anywhere).

## Rollout

- Milestone #9 sub-issue split (per epic #266): config schema; registry + switch tool; static fast
  path; version-manager boot + child bridge; HTTP scoping; docs.
- Doc parity updates: README (server description + config docs), GUIDE "Multi-project" section,
  `docs/mcp-security.md` (project isolation, shim execution model), `server.json` description/count,
  CHANGELOG 6.0.0, `docs/ROADMAP.md` phase-3 status, install generator note (single-project default
  unchanged).
- Deprecation/compat: none; `enabled=false` (default) means zero behavioral change for existing
  hosts; `rails_switch_project` absent from tools list until enabled.

## Alternatives considered

- **In-process sequential boot** (rails-mcp-server-style switch inside one process): rejected —
  Rails/Zeitwerk cannot safely unload one app and boot another; constants and autoloaders leak.
- **One server per project, client-side** (status quo): rejected — solves nothing; epic exists
  because agents juggling N stdio servers is painful.
- **Fork-based isolation** (`fork` per switch): rejected — forked children complicate cleanup and
  are unavailable on some platforms; explicit spawn is auditable.
- **Static-only multi-project** (no booting): rejected as a superset trap — boot-required sections
  are the reason teams want switching at all.

## Open questions

1. Session affinity on HTTP transport: is one active project per connection (MCP session id) the
   right scope, or per-thread? (Design assumes per-request thread scope with an explicit
   session-scoped active project map; needs a spec decision at implementation time.)
2. Should `per_project` override more than `cache_ttl` (e.g. full preset per project), and if so,
   how are conflicting `disabled_introspection_categories` resolved?
3. Default child-idle timeout: 60s proposed — long enough to avoid thrash, short enough to bound
   memory; should idle children instead park (SIGSTOP) and resume on demand?
4. Does `rails_switch_project` (stateful over server session state, but read-only over the host
   app) require amending the AGENTS.md "read-only tools only" wording to "read-only over the host
   application", or should project switching move to transport-level session control outside the
   `rails_` tool namespace?
