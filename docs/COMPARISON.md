# How rails-ai-bridge compares

Rails has several projects that turn an app into AI-readable context. They
overlap, but they optimize for different things. This page states the
durable differences factually; counts were checked against each project's
published documentation at the time of writing (September 2026) and will
drift with releases.

Projects compared:

- **rails-ai-bridge** — this gem ([README](../README.md),
  [docs/GUIDE.md](GUIDE.md), https://rubygems.org/gems/rails-ai-bridge)
- **rails-ai-context** — https://rubygems.org/gems/rails-ai-context
  (docs: https://github.com/crisnahine/rails-ai-context)
- **rails-mcp-server** — https://github.com/maquina-app/rails-mcp-server,
  https://rubygems.org/gems/rails-mcp-server
- **woods** — https://rubygems.org/gems/woods
  (docs: https://github.com/lost-in-the/woods)
- **rails-hyperdrive** — https://rubygems.org/gems/rails-hyperdrive

## At a glance

| | rails-ai-bridge | rails-ai-context | rails-mcp-server | woods | rails-hyperdrive |
|---|---|---|---|---|---|
| Primary shape | Rails engine: generated context files + MCP server | Gem: MCP server + CLI + generated context files | Standalone MCP server (gem install) | Rails gem: extraction to a persistent index + MCP index server | Rails engine: MCP endpoint mounted in dev |
| MCP tools | 20 built-in read-only (`rails_*`), extensible via `additional_tools` | 45 read-only tools (MCP and CLI) | 3 bootstrap tools + internal analyzers via progressive discovery | 14 index-server tools (+9 optional console tools) | Introspection tools incl. eval Ruby, query DB, tail logs |
| Introspectors | 9 (`:standard`) / 27 (`:full`), opt-in extras | 17 (`:standard`) / 40 (`:full`) | Analyzer set, not preset-based | Extractor set covering app, framework source, GraphQL, policies | Companion-gem content system (skills, guidelines, agents, commands) |
| Generated context files | 7 targets: Claude, Cursor, Codex, Devin, Copilot, Gemini, JSON | Claude, Cursor, Copilot, OpenCode, Codex CLI | ✗ (config files only) | ✗ | Via companion gems (artifact kinds) |
| Diff-aware regeneration | ✅ SHA256 fingerprint per file; unchanged files are skipped | Regenerates files | n/a | Persistent index with incremental updates | n/a |
| Compact-by-default output | ✅ ≤150-line CLAUDE.md, detail levels `summary`/`standard`/`full` | Detail levels on most tools | ✅ Progressive discovery keeps initial context small | Pre-extracted index; queries are targeted | n/a |
| Works without booting the app | ✅ Static `db/schema.rb` parse, tagged `[INFERRED]` | ✅ Static tier: routes/schema/source with `[STATIC]` tags | ✅ Runs `bin/rails` per project for boot tools; file tools work statically | ✅ Index server reads the published index; no Rails boot needed | Needs the Rails process running |
| Semantic/static analysis | rubydex integration (`rails_search_semantic`) | Prism AST with `[VERIFIED]`/`[INFERRED]` confidence tags | Prism static analysis for models | Dependency graph, flow tracing, graph queries | ✗ |
| Dependency / call graph | ✗ | `dependency_graph` tool | ✗ | ✅ Core feature: forward/reverse deps, graph traversal, flow tracing | ✗ |
| Read-only SQL / data access | ✗ (structure introspection only) | `query` tool: read-only SQL with timeout, row limit, column redaction | ✗ | Optional console server for live data, disabled by default | Query DB tool (dev only) |
| Outbound provider federation | ✅ `rails_get_provider_context`: external MCP providers, host allowlist, SSRF controls, credential redaction, disabled by default | ✗ | ✗ | ✗ | Companion gems are the content channel |
| Multi-project | ✗ (one app per bridge) | ✗ | ✅ `projects.yml`, `switch_project` | One app per index | One app |
| Usage stats (RubyGems, September 2026) | New gem; see rubygems.org for current numbers | 43,644 total downloads | 259,094 total downloads | 3,852 total downloads | 8,155 total downloads |
| Requirements | Ruby ≥ 3.2, Rails ≥ 7.1 | Ruby ≥ 3.1, Rails ≥ 7.0 | Ruby ≥ 3.3 | Ruby ≥ 3.0, Rails 6.0–8.x | Ruby ≥ 3.2 |

Where this table marks rails-ai-bridge with ✗, the feature is not shipped
today: no dependency graph, read-only SQL tool, CLI mode, or multi-project
support.

## What each project is optimizing for

**rails-ai-bridge** optimizes for committed, compact, per-assistant context
plus a small read-only tool surface. The mental model: static files orient the
assistant at session start; 20 MCP tools answer specific questions on demand.
Diff-aware regeneration (SHA256 fingerprints) means `rails ai:bridge` is safe
to run on every change without churn, and the outbound provider stack is the
only one here designed for federating context from other MCP services under
SSRF controls. Choose it when you want per-assistant files (including Devin
and Gemini shims), committed team context, and a small, auditable tool set.

**rails-ai-context** optimizes for breadth: 45 tools, 40 introspectors, a CLI
mode, Prism AST parsing with confidence tags, and a static tier that answers
even when the app cannot boot. It also supports standalone installs without a
Gemfile entry. Choose it when you want the widest single-gem tool surface and
an SQL read path with redaction, and you do not mind a larger tool inventory.

**rails-mcp-server** optimizes for multi-project exploration from a standalone
install: configure many apps in `projects.yml`, switch between them, and keep
the client's initial context tiny via progressive tool discovery (3 bootstrap
tools). It ships framework guides (Rails, Turbo, Stimulus, Kamal) as MCP
resources. Choose it when you hop between many Rails apps from one client and
do not need generated per-assistant files committed in each repo.

**woods** optimizes for deep structural intelligence: it extracts the app
into a persistent index (units, edges, flows) and serves it from an index
server that never boots Rails. Dependency traversal and flow tracing are its
core; semantic search is optional via embeddings. Choose it when the question
is "what touches this method and how do callers flow through the app" rather
than "what files should the assistant read first."

**rails-hyperdrive** optimizes for a development-time endpoint plus an
ecosystem: it mounts MCP at `/_hyperdrive/mcp` and installs artifacts (skills,
guidelines, agents, commands) from `rails-hyperdrive-*` companion gems. Its
tool surface includes eval and DB query, so treat it as a development-only
tool. Choose it when you want capability delivered through companion gems
rather than committed context files.

## Summary

- Most tool surface: rails-ai-context (45 tools).
- Best multi-project story: rails-mcp-server.
- Deepest structural/graph analysis: woods.
- Most extensible content ecosystem: rails-hyperdrive.
- rails-ai-bridge's niche: compact per-assistant files for 7 targets,
  diff-aware regeneration, strict read-only tools, and the only outbound
  provider federation with SSRF controls — at the cost of a smaller built-in
  tool set.

Numbers and feature claims above were checked against the linked sources at
the time of writing (September 2026). If you maintain one of these projects and a row is wrong, open an
issue — corrections are welcome.
