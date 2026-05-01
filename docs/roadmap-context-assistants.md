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

## In progress

- Custom Rails directory introspection coverage gaps
- Remaining v3.1.0 context-quality slices must apply the `yard-documentation` skill:
  every new or changed public Ruby class/method needs an English summary plus `@param`,
  `@return`, and `@raise` tags where applicable before the slice is considered complete.

## Relation to versioning

**No semver bump is implied by this doc alone.** A future **major release** (e.g. 2.0.0) should follow **after** this work when the maintainers are ready to communicate breaking or wide-ranging changes to generated files and defaults — not as a fixed milestone on the MCP roadmap.

## References

- [docs/GUIDE.md](GUIDE.md) — install, formats, MCP setup
- [CHANGELOG.md](../CHANGELOG.md) — user-visible changes
