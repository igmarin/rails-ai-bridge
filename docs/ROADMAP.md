# rails-ai-bridge — Roadmap

Last updated: 2026-09-14

## Vision

rails-ai-bridge gives AI assistants an accurate, read-only map of a Rails app through committed
context files and a live MCP server. The roadmap closes the credibility gap (docs that match code),
then extends the read-only boundary safely (anti-hallucination rules, SELECT-only data tools),
then invests in distribution and deeper static intelligence. Nothing in this roadmap writes to the
host database or weakens the read-only guarantee.

## Phase 1 — v5.1.1 (milestone #7): hygiene, parity, cleanup

Epic [#244](https://github.com/igmarin/rails-ai-bridge/issues/244) — v5.1.1 Hygiene: doc parity, dedup, and repo cleanup.

| # | Issue | Description |
|---|-------|-------------|
| #245 | Stale artifacts | server.json (v3.0.0/13 tools) and CONTRIBUTING.md (19) match reality (5.1.0/20); parity specs guard both |
| #246 | Repo hygiene | delete test_table.md, fix README "once published", consolidate 3 port/registry docs, archive done docs |
| #247 | Docs truth | drop false "omakase" claim; fix AGENTS.md non_ar_models preset claim |
| #248 | RuleFileWriter | extract triplicated write-or-skip loop from 5 serializers; collapse stacked YARD blocks |
| #249 | database_size spec | dedicated spec for buckets, nil/missing-table, error wrapping |
| #250 | archspec cycle | break smallest edge in 6-component cycle; unblock Dependabot PR #242 |

## Phase 2 — v5.2 (milestone #8): rules, safe data tools, growth

Epic [#251](https://github.com/igmarin/rails-ai-bridge/issues/251) — Anti-hallucination rules injected into generated context files (default ON, config-off-able).

| # | Issue | Description |
|---|-------|-------------|
| #252 | Design + red specs | our own 5-6 rules; placement per format; toggle default enabled |
| #253 | Injection | 7 main + 5 split-rules serializers; JSON `rules` key; reuse RuleFileWriter |
| #254 | Config + docs | Output sub-config, README/GUIDE, CHANGELOG 5.2.0 |

Epic [#255](https://github.com/igmarin/rails-ai-bridge/issues/255) — Safe data tools (rails_query + rails_read_logs). Absolute guarantee: no writes, no DDL, no shell.

| # | Issue | Description |
|---|-------|-------------|
| #256 | rails_query | SELECT-only, single statement, timeout, row cap, MessageSanitizer redaction (TDD) |
| #257 | rails_read_logs | log/ allowlist tail, byte/line caps, credential redaction, detail levels (TDD) |
| #258 | Register + docs | tools #21/#22; counts 20→22 everywhere; security docs on data-access boundaries |

Epic [#259](https://github.com/igmarin/rails-ai-bridge/issues/259) — Growth & distribution.

| # | Issue | Description |
|---|-------|-------------|
| #260 | examples/ | runnable sample app + docs/EXAMPLES.md; new user live in <5 min |
| #261 | MCP Registry | validate server.json against official schema, submit listing, README badge |
| #262 | Hosted docs | YARD to GitHub Pages on tag push with latest banner |
| #263 | Positioning | docs/COMPARISON.md + README rewrite; factual, cited, no disparagement |

## Phase 3 — v6.0 (milestone #9): design-doc epics (sub-issues created when phase starts)

| # | Epic | Description |
|---|------|-------------|
| #264 | Prism confidence tags | optional Prism static pass; `[VERIFIED]`/`[INFERRED]` tags per response section; design doc first |
| #265 | Dependency graph | introspector + `rails_get_dependency_graph` tool (woods-style edges); design doc first |
| #266 | Multi-project | `switch_project`, version-manager-aware booting; config-server rework design doc first |

## Backlog (unscheduled)

- **Static tier + `[STATIC]` tags** — pure-AST fallback when runtime reflection is unavailable; pairs with #264.
- **`search_code` trace mode** — show which file/line each context fact came from, for auditability.
- **Live resource templates** — MCP resource templates for on-demand slices without regenerating files.
- **Multi-tool presets** — bundle tools into named presets (e.g. `:api_audit`) for smaller tool surfaces.
- **AS::Notifications per tool call** — instrument every tool call for latency/usage metrics.
- **OpenCode + VS Code serializer targets** — extend per-assistant serializer breadth to two more tools.
- **Companion-gem skills ecosystem (hyperdrive-style)** — optional companion gems shipping skills/recipes for specific stacks.

## Competitor scan (summary)

Full analysis lands in docs/COMPARISON.md via [#263](https://github.com/igmarin/rails-ai-bridge/issues/263).

| Gem | Notable | Source |
|-----|---------|--------|
| rails-ai-context v5.26.0 | 45 tools, Prism confidence tags, static tier, ~43.6k downloads | https://rubygems.org/gems/rails-ai-context |
| rails-mcp-server | multi-project, progressive discovery, ~259k downloads | https://github.com/maquina-app/rails-mcp-server |
| woods | dependency graph intelligence | https://rubygems.org/gems/woods |
| rails-hyperdrive | companion-gem content model | https://rubygems.org/gems/rails-hyperdrive |
