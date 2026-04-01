# Upgrading rails-ai-bridge

## Upgrading from 1.x to 2.x

**No configuration changes required.** Every `config.*` attribute from 1.x is still available — `Configuration` now delegates to focused sub-objects but exposes the same flat DSL. See `CHANGELOG.md` for the full list of internal changes.

---

## New in 2.x — `config.mcp` settings

MCP HTTP operational configuration lives under `config.mcp` (a `Config::Mcp` object). All attributes are also accessible as flat delegators on `config` directly.

### Rate limiting

```ruby
RailsAiBridge.configure do |config|
  # Explicit ceiling: 100 requests per 60-second sliding window per client IP
  config.mcp.rate_limit_max_requests  = 100
  config.mcp.rate_limit_window_seconds = 60

  # Set to 0 to disable rate limiting entirely
  # config.mcp.rate_limit_max_requests = 0
end
```

When `rate_limit_max_requests` is `nil` (default), the gem may apply an **implicit** per-IP ceiling from `security_profile` (`:strict` / `:balanced` / `:relaxed`), unless `mode` suppresses it:

- **`mode: :dev`** — no implicit limit.
- **`mode: :hybrid`** (default) — implicit limit only when `Rails.env.production?`.
- **`mode: :production`** — implicit limit in every Rails environment.

Set `config.mcp.rate_limit_max_requests = 0` to **disable** limiting entirely (including implicit). A **positive integer** always overrides the profile.

> **Note:** the rate limiter is **in-memory and per-process**. It is not shared across Puma workers or hosts. Use a reverse proxy, WAF, or `rack-attack` for strict distributed quotas.

### Structured logging

```ruby
RailsAiBridge.configure do |config|
  # Emit one JSON line per MCP HTTP response to Rails.logger
  config.mcp.http_log_json = true
end
```

Each log line includes `msg`, `event`, `http_status`, `path`, `client_ip`, and `request_id` (when present). Tokens and full Rack `env` are never logged. The flag is read **on each request** (unlike the rate-limit snapshot taken at `HttpTransportApp.build`).

### Post-auth authorization (`authorize`)

```ruby
RailsAiBridge.configure do |config|
  # Called after successful auth; returning falsey yields HTTP 403
  config.mcp.authorize = ->(context, request) {
    context[:role] == "admin"
  }
end
```

The lambda is read and called **on every request** (like `http_log_json`), so changes take effect immediately without rebuilding the transport app. If the lambda raises a `StandardError`, the gem treats it as a 403 and logs the error — it does not propagate as a 500.

### Production boot guard

```ruby
RailsAiBridge.configure do |config|
  # Raise at boot in production unless an auth mechanism is configured
  config.mcp.require_auth_in_production = true
end
```

When `true` in a production environment, Rails boot fails unless at least one MCP HTTP auth mechanism is configured:
- `config.http_mcp_token`, or
- `ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]`, or
- `config.mcp_token_resolver`, or
- `config.mcp_jwt_decoder`

Default is `false`.

---

## `strategy :bearer_token` misconfiguration guard

Rails **boot** raises `RailsAiBridge::ConfigurationError` if you configure `:bearer_token` strategy without a resolver or static token — that combination would leave HTTP MCP unauthenticated.

---

## Resolver / JWT return values

Return **`nil`** (or `false`) when a token is invalid. Returning `false` explicitly is treated as auth failure (401).
