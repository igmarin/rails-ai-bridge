# Roadmap: MCP HTTP auth (v2 track)

High-level direction for the `RailsAiBridge::Mcp` HTTP authentication layer, rate limiting, and related docs. The detailed task list may live in your issue tracker or in Cursor plans; this file is the **human-readable** anchor for contributors.

## Engineering principles (this track)

These are **priorities** for code that lands under `lib/rails_ai_bridge/mcp/` and related Rack paths—not optional polish at the end.

1. **Tests gate implementation** — Write or extend a failing spec for the behavior, run it, then implement (`rspec-best-practices`, `rails-agent-skills`). No “implement first, test later” for new behavior.

2. **Principles and YARD go together** — Treat **`rails-principles-and-boundaries`** and **`yard-documentation`** as one bar for each slice that touches library code:
   - **Behavior & structure:** **KISS**; **DRY** only when duplication has a real maintenance cost; **style** from the repo linter (e.g. RuboCop omakase)—do not restate linter rules in prose.
   - **API documentation (same PR / same slice):** Any new or changed **public** Ruby surface (classes, public methods) needs **English** YARD: summary line plus `@param`, `@return`, and `@raise` when applicable—**before** the change is considered done, not in a follow-up ticket. Use `@example` when usage is non-obvious.
   - **Private helpers:** Document when behavior is non-obvious (e.g. lambdas that must not raise, digest-normalized comparison for timing safety).

3. **Clear method boundaries** — Keep Rack/guard logic separate from “run host lambda safely” (e.g. private `decode_token` / `resolve_token_context`) so strategies stay easy to read, review, and extend with new strategies without growing god methods.

4. **Self-review before merge** — Run through `rails-code-review` (and security/architecture skills when touching auth or production boot). Confirm YARD on touched public API matches the **yard-documentation** gate.

5. **User-facing documentation per slice** — Update `CHANGELOG` `[Unreleased]`, and touch `GUIDE` / `SECURITY` / `UPGRADING` when user-visible behavior changes.

## Done vs upcoming (snapshot)

Already in tree (check `CHANGELOG.md`): `Mcp::HttpAuth`, `BearerToken`, `Jwt`, `config.mcp`, `authorize`, production validations, resolver/JWT error handling, `:bearer_token` boot guard, optional **in-process IP rate limit** on the MCP HTTP path (`Mcp::HttpRateLimiter`, `HttpTransportApp`).

**Typical next slices:** structured logging, `security_profile` presets, release **2.0.0** consolidation (README upgrading, version bump, generator template).

## References

- [docs/GUIDE.md](GUIDE.md) — MCP HTTP configuration
- [SECURITY.md](../SECURITY.md) — threat model and production notes
- [UPGRADING.md](../UPGRADING.md) — breaking / new config knobs
- Contributor skills (Cursor / team): **`rails-principles-and-boundaries`**, **`yard-documentation`** — use both for MCP/auth work; they are intentionally paired in section 2 above.
