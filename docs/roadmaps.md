# Roadmaps — progress index

Entry point to see **which tracks exist** and **what is left**. Details live in each linked file;
update the tables here when you close slices (or track work in GitHub Issues / Projects instead).

**Audience:** These documents are mainly for **maintainers and contributors**. Gem users usually rely
on [GUIDE.md](GUIDE.md), [CHANGELOG.md](../CHANGELOG.md), and the README. Keeping roadmaps **in git**
is normal for open-source gems (transparency, onboarding); they are not required to *use* the gem.

## MCP HTTP track (`RailsAiBridge::Mcp`)

**Primary doc:** [roadmap-mcp-v2.md](roadmap-mcp-v2.md) (engineering principles + narrative snapshot).

| Area | Status |
|------|--------|
| Auth (`Mcp::Authenticator`, Bearer, JWT, resolver, boot guards) | Done |
| `authorize` + 403 | Done |
| In-process rate limit + bucket prune (`Mcp::HttpRateLimiter`) | Done |
| `mode` / `security_profile` + effective limits (`Config::Mcp`) | Done |
| JSON HTTP logging (`http_log_json`, `Mcp::HttpStructuredLog`) | Done |
| Docs (GUIDE / SECURITY / UPGRADING / CHANGELOG) for the above | Done |

**Optional / follow-up (non-blocking):** log sampling, metrics hooks, heavier load testing, community-driven tweaks.

---

## v2.0.0 — context files & assistant UX

**Primary doc:** [roadmap-context-assistants.md](roadmap-context-assistants.md).

| Area | Status |
|------|--------|
| Serializer formatter extraction (37 `Formatters::*` classes) | Done |
| `Config::Auth`, `Config::Server`, `Config::Introspection`, `Config::Output` façade | Done |
| `Config::Mcp` sub-object for MCP HTTP config | Done |
| `Mcp::Authenticator` consolidation | Done |
| Provider serializers extracted to `Serializers::Providers::` | Done |
| `SectionFormatter` template method base (DRY guard pattern) | Done |
| Major release (2.0.0) | Done |

---

## v2.1.0 — Gemini & Harmonization

| Area | Status |
|------|--------|
| Gemini Support (`GEMINI.md`, `GeminiSerializer`, Rake task) | Done |
| Context Harmonization (Shared `BaseProviderSerializer`) | Done |
| Enhanced directive guidance for all assistants | Done |
| Release (2.1.0) | Done |

---

## v3.1.0 — context quality

| Area | Status |
|------|--------|
| Task-relevance model ordering across compact serializers | Done |
| Bounded endpoint-focus summaries with MCP drill-down hints | Done |
| Optional PostgreSQL size buckets for `database_stats` | Done |
| Fixture matrix for standard CRUD, large schema, API-only, Hotwire, engine-style, and regulated contexts | Done |
| Real Rails-shaped fixture trees for API-only, Hotwire, large-schema, engine-style, and regulated/no-domain-metadata app profiles | Done |
| MCP large-payload checks for truncation, pagination hints, and section-cache reuse | Done |
| Secret-bearing config path filtering for generated context, conventions output, and MCP resource reads | Done |
| Convention detector coverage for custom Rails directory paths without absolute path leakage | Done |
| Model and non-AR model introspection coverage for custom `app/models` paths | Done |
| Controller, view, Stimulus, and Turbo coverage for configured Rails paths | Done |
| View detail MCP tool/resource reads for configured `app/views` paths | Done |
| Specialized Active Storage, Action Text, Config, Auth, and API scans for configured Rails paths | Done |
| README/BEST_PRACTICES clarity pass for value and setup paths | Done |
| Implementation gate for remaining 3.1.0 slices: tests, Reek/RuboCop, `yard-documentation`, and docs updates | Required |

---

## Where to look in the repo

| Need | File |
|------|------|
| Implementation rules (tests, YARD, docs per slice) | [roadmap-mcp-v2.md](roadmap-mcp-v2.md) § Engineering principles |
| What the MCP stack already includes (narrative) | [roadmap-mcp-v2.md](roadmap-mcp-v2.md) § Done vs upcoming |
| Plan for generated context (CLAUDE.md, rules, etc.) | [roadmap-context-assistants.md](roadmap-context-assistants.md) |
| User-facing shipped / upcoming changes | [CHANGELOG.md](../CHANGELOG.md) `[Unreleased]` and version sections |
