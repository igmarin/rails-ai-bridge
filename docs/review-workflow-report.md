# Review workflow report — rails-ai-bridge

Generated while executing the *Workflow revisión gema* plan: security and architecture findings, conventions, edge-case test coverage, and a prioritized backlog.

## 1. Security (rails-security-review)

| Severity | Finding | Location | Notes / existing mitigation |
|----------|---------|----------|----------------------------|
| Medium–high | HTTP MCP surface exposes full introspection if auth fails or the token leaks | [`lib/rails_ai_bridge/http_transport_app.rb`](lib/rails_ai_bridge/http_transport_app.rb), [`lib/rails_ai_bridge/mcp/authenticator.rb`](lib/rails_ai_bridge/mcp/authenticator.rb) | Specs cover 401/403/429. Production: [`validate_http_mcp_server_in_production!`](lib/rails_ai_bridge.rb). Recommended operational runbook (token, network, no public exposure). |
| Medium | `rails_search_code` passes regex to `rg` / `Regexp.new`: CPU cost risk (theoretical ReDoS) with pathological patterns | [`lib/rails_ai_bridge/tools/search_code.rb`](lib/rails_ai_bridge/tools/search_code.rb) | `max_results` is capped; Ruby fallback rescues `RegexpError`. Consider a timeout or `pattern` length limit if real abuse appears. |
| Medium | Search scoped to `Rails.root` via `realpath` + prefix | Same file | Covered in specs (`path` traversal). Consider symlinks escaping root in unusual environments. |
| Low | `ViewFileAnalyzer` uses `expand_path` + string prefix; symlinks under `app/views` pointing outside warrant hardening with `realpath` | [`lib/rails_ai_bridge/view_file_analyzer.rb`](lib/rails_ai_bridge/view_file_analyzer.rb) | New specs in [`spec/lib/rails_ai_bridge/view_file_analyzer_spec.rb`](../spec/lib/rails_ai_bridge/view_file_analyzer_spec.rb) for `..`, absolute paths, and ENOENT. |
| Informational | `AssistantFormatsPreference` uses `YAML.safe_load` with permitted classes | [`lib/rails_ai_bridge/assistant_formats_preference.rb`](lib/rails_ai_bridge/assistant_formats_preference.rb) | Sound pattern; existing specs for invalid YAML and formats. |
| Informational | `overrides.md` and generated context must not contain secrets | [`SharedAssistantGuidance`](lib/rails_ai_bridge/serializers/shared_assistant_guidance.rb) | Host team responsibility; document in install guide if needed. |

## 2. Architecture (rails-architecture-review)

### Main boundaries

- **Input:** MCP (`Server` + `HttpTransportApp` / stdio) and `rails ai:bridge` tasks → **Introspector** produces a context `Hash`.
- **Live reads:** `Tools::*` consume cached context or the tree under `Rails.root`.
- **Static output:** `Serializers::*` write markdown/JSON and split rules under `.cursor`, `.github`, etc.

### Drift / sources of truth (compact copy)

| Component | Role vs `SharedAssistantGuidance` |
|-----------|-----------------------------------|
| [`BaseProviderSerializer`](lib/rails_ai_bridge/serializers/providers/base_provider_serializer.rb) | Footer via `compact_engineering_rules_footer_lines(context)`; other sections are local (`render_stack_overview`, etc.). |
| [`RulesSerializer`](lib/rails_ai_bridge/serializers/providers/rules_serializer.rb), [`CopilotSerializer`](lib/rails_ai_bridge/serializers/providers/copilot_serializer.rb), [`CodexSerializer`](lib/rails_ai_bridge/serializers/providers/codex_serializer.rb) | Shared engineering + repo guidance; Copilot/Codex add `performance_security_and_rails_examples_lines`. |
| [`RulesOrchestrator`](lib/rails_ai_bridge/serializers/providers/rules_orchestrator.rb) | Same shared copy base + `McpToolReferenceFormatter`; **custom** stack/overview gated on `app_overview`; does not inherit from `BaseProviderSerializer`. |
| [`CursorRulesSerializer`](lib/rails_ai_bridge/serializers/providers/cursor_rules_serializer.rb) | `cursor_engineering_mdc_body_lines` + overrides pointer. |

**Risk:** changes to “compact” sections may land only on `BaseProviderSerializer` or only on `RulesOrchestrator`. When adding global bullets, update **SharedAssistantGuidance** and re-check the orchestrator vs serializers that do not share the same pipeline.

### Loading (`require_relative` vs Zeitwerk)

[`RulesOrchestrator`](lib/rails_ai_bridge/serializers/providers/rules_orchestrator.rb) uses `require_relative "../shared_assistant_guidance"`. The rest of the gem relies on Zeitwerk. Suggested convention: new providers under `serializers/providers/` may follow the orchestrator pattern only when breaking a circular dependency; otherwise prefer autoload.

## 3. Conventions (rails-code-conventions)

- **Style:** `bundle exec rubocop` (repo source of truth).
- **RSpec:** `verify_partial_doubles` — stub real constants (`RailsAiBridge::Serializers::SharedAssistantGuidance`, not a made-up namespace).
- **HTTP logging:** optional structured JSON already covered in [`http_transport_app_spec.rb`](../spec/lib/rails_ai_bridge/http_transport_app_spec.rb).

## 4. Edge cases and tests

| Area | Case | Coverage |
|------|------|----------|
| SearchCode | Traversal, invalid `file_type`, invalid regex (Ruby fallback), `max_results` | [`search_code_spec.rb`](../spec/lib/rails_ai_bridge/tools/search_code_spec.rb) |
| ViewFileAnalyzer | Valid path, `..`, absolute path outside views, missing file | [`view_file_analyzer_spec.rb`](../spec/lib/rails_ai_bridge/view_file_analyzer_spec.rb) |
| HttpTransportApp | 404, 401, 403, 429, authorize raising, logging | [`http_transport_app_spec.rb`](../spec/lib/rails_ai_bridge/http_transport_app_spec.rb) |
| AssistantFormatsPreference | Invalid YAML, empty formats, unknown keys | [`assistant_formats_preference_spec.rb`](../spec/lib/rails_ai_bridge/assistant_formats_preference_spec.rb) |
| Backlog | Symlink escaping `app/views` or `Rails.root` in SearchCode; empty or very long pattern; huge views (memory) | See section 5 |

## 5. Prioritized backlog (improvements)

1. **P0 — Operations:** Short doc “MCP HTTP in production” (token, network, `require_auth_in_production`, rate limit). Optional: link from README or `docs/`.
2. **P1 — Defensive security:** `ViewFileAnalyzer` using `File.realpath` when the file exists, compared to `realpath(views_root)`, for symlink hardening.
3. **P1 — CPU abuse:** `pattern` length cap in `SearchCode` and/or documented timeout for `rg`.
4. **P2 — Architecture:** Note in `CLAUDE.md` or serializer docs: matrix “output format → involved classes” to avoid orchestrator vs `BaseProviderSerializer` drift.
5. **P2 — Tests:** Minimal integration specs for symlinks (only if P1 lands on analyzer/search).
6. **P3 — DX:** Table “format → generated file paths” in `docs/` (aligned with enriched-context roadmap).

### Skills useful for breaking down the backlog

- **generate-tasks** / **ticket-planning:** turn P0–P3 items into tickets with paths and commands (`bundle exec rspec`, `rubocop`).
- **create-prd:** if P1/P2 bundle into a “MCP + path hardening” initiative.
- **rspec-best-practices** / **rails-tdd-slices:** when adding symlink specs or `pattern` limits.

---

*Last updated: workflow review plan (implemented in repo).*
