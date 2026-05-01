# Roadmap: context files & assistant UX (pre–major release)

This track is **separate** from [roadmap-mcp-v2.md](roadmap-mcp-v2.md) (MCP HTTP auth, rate limits, logging). It covers **improving the static context** the gem generates (CLAUDE.md, Cursor rules, Copilot instructions, etc.) so IDEs and AI clients get **clearer, more actionable** help from the same introspection data.

**Progress summary:** [roadmaps.md](roadmaps.md).

## Goals (high level)

- Sharpen per-assistant formats (structure, length, cross-links) based on real usage feedback.
- Reduce duplication and noise while keeping "always-on" rules discoverable.
## Done

- Separate LLM provider serializers from domain infrastructure (done: `Serializers::Providers::` namespace).
- DRY the formatter hierarchy (done: `SectionFormatter` template method base).
- Align tool references and workflow hints across Claude, Cursor, Copilot, Windsurf, Codex, and **Gemini** (v2.1.0).
- Refactor provider serializers with a shared `BaseProviderSerializer` for consistent, high-fidelity output (v2.1.0).
- Rank compact context by task relevance: semantic tier, structural complexity, endpoint density, recent migrations, and optional database-size hints (v3.1.0).
- Add bounded endpoint-focus summaries and context-quality fixture matrix coverage for common Rails app shapes (v3.1.0).
- Back the matrix with real Rails-shaped fixture trees for API-only, Hotwire, large-schema, engine-style, and regulated/no-domain-metadata applications (v3.1.0).
- Add MCP large-payload stability checks for truncation, pagination hints, and section-cache reuse (v3.1.0).
- Filter secret-bearing config paths from generated context, `rails_get_conventions`, and `rails://conventions` output (v3.1.0).
- Honor configured Rails paths in convention detection so custom `app/models` and `app/services`
  locations still produce useful architecture and directory-structure context without exposing absolute paths (v3.1.0).
- Honor configured `app/models` paths in ActiveRecord source metadata and `non_ar_models`
  discovery, mapping custom filesystem locations back to stable logical paths in generated context (v3.1.0).
- Honor configured controller and frontend paths in controller metadata, view summaries,
  Stimulus controllers, and Turbo frame/stream/broadcast discovery (v3.1.0).
- Honor configured `app/views` paths in file-level view detail reads for `rails_get_view(path:)`
  and `rails://views/{path}` while preserving traversal checks (v3.1.0).
- Honor configured Rails paths in specialized Active Storage, Action Text, Config, Auth, and API
  scans so attachments, rich text fields, CurrentAttributes, API layers, and auth/policy signals
  remain useful in non-conventional app layouts (v3.1.0).

## In progress

- Custom Rails directory introspection coverage gaps outside model, controller, view, Stimulus,
  Turbo, convention, Active Storage, Action Text, Config, Auth, API, and view detail detection
- Remaining v3.1.0 context-quality slices must apply the `yard-documentation` skill:
  every new or changed public Ruby class/method needs an English summary plus `@param`,
  `@return`, and `@raise` tags where applicable before the slice is considered complete.

## Custom Path Support Coverage

For **v3.1.0**, custom Rails path support is considered complete for the default `:standard`
context-quality promise and the highest-value `:full` signals:

- **Standard preset coverage:** `models`, `controllers`, and `conventions` honor configured Rails
  paths where those introspectors read application source. `schema`, `routes`, `jobs`, `gems`,
  `tests`, and `migrations` are not primarily driven by `app.paths`.
- **High-value full-preset coverage:** `non_ar_models`, `views`, `stimulus`, `turbo`,
  `active_storage`, `action_text`, `config`, `auth`, `api`, and file-level view detail reads honor
  configured logical Rails paths where they scan source files.
- **Deferred parity candidates:** `assets`, `i18n`, `rake_tasks`, `action_mailbox`, `devops`,
  and `middleware` remain full-preset follow-up candidates. Treat these as targeted future work
  when a real fixture or user app shows custom path value, not as a blocker for the 3.1.0 release.

## Relation to versioning

**No semver bump is implied by this doc alone.** A future **major release** (e.g. 2.0.0) should follow **after** this work when the maintainers are ready to communicate breaking or wide-ranging changes to generated files and defaults — not as a fixed milestone on the MCP roadmap.

## References

- [docs/GUIDE.md](GUIDE.md) — install, formats, MCP setup
- [CHANGELOG.md](../CHANGELOG.md) — user-visible changes
