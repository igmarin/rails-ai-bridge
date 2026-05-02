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

## Release closure

The v3.1.0 context-quality implementation is complete for the default `:standard` preset and the
highest-value generated-context signals. Before merging or tagging the release, run the final gate:

- `rtk bundle exec rspec`
- `env PERF=true rtk bundle exec rspec --tag perf`
- `rtk bundle exec rubocop --cache false --format simple`
- `rtk bundle exec reek`
- `rtk bundle exec reek spec/fixtures/apps`
- `rtk bundle exec yard stats --list-undoc`

Any future code-producing slice should continue to apply the `yard-documentation` skill: every new
or changed public Ruby class/method needs an English summary plus `@param`, `@return`, and `@raise`
tags where applicable before the slice is considered complete.

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

## Documentation readability recommendations

Because this gem serves Rails developers with different experience levels, documentation should
prefer a layered path over one large linear read:

- **README:** keep as the shortest product path: problem, value, quick start, generated files,
  common presets, and safe MCP setup. Link out before diving into every option.
- **Best Practices:** make this the "how to get value" guide: choosing a preset, reading generated
  context, writing useful overrides, and avoiding token/security pitfalls.
- **Guide:** keep exhaustive reference material here: every command, config option, MCP tool, and
  generated file behavior.
- **Security docs:** keep threat-model and deployment advice out of the README except for clear
  links and short warnings.
- **Examples:** add small scenario-first examples over time, such as API-only, Hotwire CRUD,
  regulated app, and large-schema CRM. These are easier for new users to follow than option tables.

## Relation to versioning

**No semver bump is implied by this doc alone.** A future **major release** (e.g. 2.0.0) should follow **after** this work when the maintainers are ready to communicate breaking or wide-ranging changes to generated files and defaults — not as a fixed milestone on the MCP roadmap.

## References

- [docs/GUIDE.md](GUIDE.md) — install, formats, MCP setup
- [CHANGELOG.md](../CHANGELOG.md) — user-visible changes
