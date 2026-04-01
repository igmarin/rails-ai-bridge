# Roadmap: MCP HTTP auth (v2 track)

High-level direction for the `RailsAiBridge::Mcp` HTTP authentication layer, rate limiting, and related docs. The detailed task list may live in your issue tracker; this file is the **human-readable** anchor for contributors.

## Engineering principles (this track)

These are **priorities** for code that lands under `lib/rails_ai_bridge/mcp/` and related Rack paths — not optional polish at the end.

1. **Tests gate implementation** — Write or extend a failing spec for the behavior, run it, then implement. No "implement first, test later" for new behavior.

2. **YARD on every public surface** — Any new or changed public Ruby class or method needs an English YARD summary, `@param`, `@return`, and `@raise` when applicable — before the change is considered done.

3. **Clear method boundaries** — Keep Rack/guard logic separate from "run host lambda safely." Strategies stay easy to read, review, and extend without growing god methods.

4. **Self-review before merge** — Run through `rails-code-review` (and security/architecture skills when touching auth or production boot).

5. **User-facing documentation per slice** — Update `CHANGELOG` `[Unreleased]`, and touch `GUIDE` / `SECURITY` / `UPGRADING` when user-visible behavior changes.

## Done (v2 snapshot)

- `Mcp::Authenticator` — consolidated strategy resolution (replaces `McpHttpAuth` + `Mcp::HttpAuth`)
- `Mcp::Auth::Strategies::BearerToken` — static token + optional `token_resolver`, digest compare
- `Mcp::Auth::Strategies::Jwt` — host-supplied `jwt_decoder`; no JWT gem bundled
- `Config::Auth` — flat auth sub-config (`http_mcp_token`, `mcp_token_resolver`, `mcp_jwt_decoder`)
- `Config::Mcp` — MCP HTTP operational config (`rate_limit_*`, `http_log_json`, `authorize`, `require_auth_in_production`, `mode`, `security_profile`)
- `Mcp::HttpRateLimiter` — in-process sliding window per IP, mutex, prune empty buckets
- `Mcp::HttpStructuredLog` — one JSON line per MCP HTTP outcome; no token logging
- `HttpTransportApp` — single Rack entry: path match → auth → authorize → rate limit → log → transport
- Boot / config validation — `:bearer_token` requires resolver or static token; `require_auth_in_production` alignment
- Docs: GUIDE / SECURITY / UPGRADING / CHANGELOG / roadmaps

## Next (follow-up, non-blocking)

- Log sampling (emit every Nth request instead of every request)
- Metrics hooks (expose request counts / rate-limit hits for APM)
- Heavier load testing / benchmarks
- Community-driven tweaks (e.g. per-route rate limits, response-size logging)

## References

- [docs/roadmaps.md](roadmaps.md) — quick progress tables for all tracks
- [docs/GUIDE.md](GUIDE.md) — MCP HTTP configuration
- [docs/roadmap-context-assistants.md](roadmap-context-assistants.md) — IDE / context file improvements
- [SECURITY.md](../SECURITY.md) — threat model and production notes
- [UPGRADING.md](../UPGRADING.md) — breaking / new config knobs
