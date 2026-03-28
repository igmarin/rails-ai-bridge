# Upgrading rails-ai-bridge

This file will grow with major releases (especially 2.x). Early sections document new MCP configuration knobs.

## `config.mcp.require_auth_in_production`

When set to `true` in a **production** environment, Rails boot fails unless at least one MCP HTTP auth mechanism is configured:

- `config.http_mcp_token`, or
- `ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]`, or
- `config.mcp.auth.token_resolver` (lambda that maps the raw Bearer string to a non-nil context), or
- `config.mcp.auth.jwt_decoder` (lambda that returns a payload or `nil`; use your preferred JWT gem inside the lambda).

Default is `false` (same effective behavior as before for apps that do not opt in).

## `strategy :bearer_token`

Rails **boot** raises `RailsAiBridge::ConfigurationError` if **all** of the following are true:

- `config.mcp.auth.strategy == :bearer_token`
- `config.mcp.auth.token_resolver` is blank
- Neither `config.http_mcp_token` nor `ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]` is set

That combination would leave HTTP MCP **unauthenticated**. Fix by adding a resolver or a static token.

## Resolver / JWT return values

Use **`nil`** (or let the gem treat **`false`** as failure) when a token is invalid. Returning `false` explicitly is treated the same as `nil` for auth failure (401).

## `config.mcp` (overview)

Inside `RailsAiBridge.configure`:

- `config.mcp.auth_configure { |a| ... }` — set `a.strategy` (`:jwt`, `:bearer_token`, `:static_bearer`, or `nil` for auto), `a.token_resolver`, `a.jwt_decoder`, etc.
- `config.mcp.authorize` — optional `->(context, request) { truthy }` after successful auth; returning falsey yields HTTP 403 on the MCP path.

See [docs/GUIDE.md](docs/GUIDE.md) for full MCP HTTP documentation.

## MCP HTTP `mode`, `security_profile`, and rate limits

When `config.mcp.rate_limit_max_requests` is **`nil`**, the gem may apply an **implicit** per-IP ceiling from `security_profile` (`:strict` / `:balanced` / `:relaxed`), unless `mode` suppresses it:

- **`dev`** — no implicit limit.
- **`hybrid`** (default) — implicit limit only when `Rails.env.production?` is true.
- **`production`** — implicit limit in every Rails environment (useful to mimic prod throttling locally).

Set **`config.mcp.rate_limit_max_requests = 0`** to **disable** limiting entirely (including implicit). A **positive integer** always overrides the profile.

## MCP HTTP structured logging

`config.mcp.http_log_json = true` emits **one JSON line per MCP HTTP response** (`msg` key `rails_ai_bridge.mcp.http`, plus `event`, `http_status`, `path`, `client_ip`, and `request_id` when present). Tokens and full Rack `env` are not logged. This flag is read **on each request** (unlike the rate-limit snapshot at `HttpTransportApp.build`).
