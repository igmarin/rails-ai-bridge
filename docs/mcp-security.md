# MCP HTTP security notes

Operational guidance for hosts using rails-ai-bridge MCP over HTTP.

## Treat the MCP token like a production secret

A valid Bearer token (or JWT accepted by your decoder) grants access to read-only tools that expose schema, routes, source layout, selected file contents via tools, and static MCP resources. Store tokens in encrypted credentials or a secrets manager; do not commit them to git.

## Prefer authentication on any network-exposed HTTP endpoint

By default, HTTP MCP allows anonymous access when no auth strategy is configured (backward compatible for local development). For servers reachable beyond localhost, set `config.mcp.require_http_auth = true` so unconfigured deployments return `401`, or configure `http_mcp_token`, `mcp_token_resolver`, or `mcp_jwt_decoder`. In production, also use `validate_http_mcp_server_in_production!` / `require_auth_in_production` as documented in the main README.

In non-production environments, the standalone HTTP MCP server prints a one-time stderr warning when it starts without authentication to make the default behavior visible.

## JWT authentication with short-lived tokens

`http_mcp_token` is a static bearer token: rotating it means redistributing a secret to every client. For deployments that need rotation or expiry, configure `config.mcp_jwt_decoder` instead — the highest-priority auth strategy. The gem carries **no JWT dependency**: you supply a lambda that decodes (and verifies) the token.

```ruby
# config/initializers/rails_ai_bridge.rb
require "jwt" # the host app's own jwt gem

RailsAiBridge.configure do |config|
  config.mcp.require_http_auth = true

  config.mcp_jwt_decoder = ->(token) do
    payload, _header = JWT.decode(
      token,
      Rails.application.credentials.jwt_mcp_secret!,
      true,                          # verify signature
      algorithm: "HS256",
      verify_expiration: true        # reject expired tokens (default when verifying)
    )
    payload                          # truthy payload => authenticated
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil                              # nil => 401 unauthorized
  end
end
```

Decoder contract:

- Return a **truthy payload** (Hash recommended) — request is authenticated; the payload is exposed to authorization hooks.
- Return **`nil`** or **`false`** — request is rejected with `401` (`:unauthorized`).
- **Raise** — treated as `:decode_error`, also `401`; the exception never propagates.

### Token rotation strategy

- **Short expiry, frequent re-issue.** Issue MCP tokens with a 5–15 minute `exp` from your existing login/session flow. A leaked token expires on its own; there is nothing to rotate per incident.
- **Signing-key rotation.** When rotating the HMAC secret (or moving to RS256/JWKS), accept both keys during the overlap window:

  ```ruby
  config.mcp_jwt_decoder = ->(token) do
    keys = [Rails.application.credentials.jwt_mcp_secret!,
            Rails.application.credentials.jwt_mcp_secret_previous!]
    keys.lazy.filter_map do |key|
      JWT.decode(token, key, true, algorithm: "HS256").first
    rescue JWT::DecodeError, JWT::ExpiredSignature
      nil
    end.first
  end
  ```

  Retire the previous key once all clients have re-issued tokens.
- **Immediate revocation.** Stateless JWTs cannot be revoked; if you need it, combine short `exp` with your own denylist check inside the decoder (return `nil` for revoked subjects).
- **Client capability note.** Some AI hosts cannot refresh tokens and work best with a long-lived static token or `mcp_token_resolver` (which can consult a secret manager per request). Pick the strategy per client: JWT for short-lived machine-to-machine auth, `mcp_token_resolver` when the credential lives in a vault, `http_mcp_token` only for local development.

## Rate limiting and proxies

Built-in rate limiting keys off the Rack request IP. Behind reverse proxies, configure Rails `trusted_proxies` so `request.ip` reflects the real client; otherwise limits may apply to the wrong address or be bypassed.

### Single-process deployments

The default in-memory limiter works for one Puma worker or a single-process server. Configure the ceiling and window via `config.mcp.rate_limit_max_requests` and `config.mcp.rate_limit_window_seconds`.

### Multi-process or multi-host deployments

The default in-memory limiter is not shared across Puma workers or hosts. For distributed deployments, plug in `RailsAiBridge::Mcp::CacheRateLimiter`, which uses `Rails.cache` (Redis, Memcached, etc.) as the shared counter backend:

```ruby
RailsAiBridge.configure do |config|
  config.mcp.rate_limiter = RailsAiBridge::Mcp::CacheRateLimiter.new(
    max_requests: 300,
    window_seconds: 60,
    cache: Rails.cache,
    key_prefix: "rab:rl"
  )
end
```

Alternatively, use `Rack::Attack` in front of the MCP endpoint for centralized, proxy-aware throttling:

```ruby
class Rack::Attack
  throttle("mcp/ip", limit: 300, period: 60) do |request|
    request.ip if request.path == "/mcp"
  end
end
```

## Optional authorization after auth

`config.mcp.authorize` can return false to issue `403` for otherwise valid tokens (e.g. tenant or role checks).

## Stdio transport

The stdio MCP server has no Bearer layer; anyone who can run the process can use the tools. Use isolated users or containers if multiple tenants share a host.

### Threat model

| Assumption | Implication |
|------------|-------------|
| The host operating system controls who can execute `rails ai:serve`. | Anyone with shell access to the Rails app can invoke every `rails_*` MCP tool and read the returned context. |
| The stdio transport is local to the process. | Network attackers cannot reach stdio directly, but a compromised local account or shared development container bypasses this boundary. |
| AI clients run with the same privileges as the user who launched them. | A malicious or misconfigured client can exfiltrate schema, routes, source code, and any file the user can read. |

### Recommendations

- Run MCP-enabled Rails processes under dedicated, least-privilege OS accounts.
- In shared development containers or CI runners, avoid mixing users who should not see each other's application context.
- Do not mount sensitive credentials files or SSH keys into containers that run the MCP server unless those tools genuinely need them.
- Prefer HTTP MCP with authentication when multiple users or services share a host and need access controls beyond the OS.

## See also

- [SECURITY.md](../SECURITY.md) — reporting vulnerabilities and design summary
- [docs/GUIDE.md](GUIDE.md) — full configuration and MCP tool reference
- [docs/v5/context-providers-design.md](v5/context-providers-design.md) — outbound provider design and security model

## Outbound context provider security (v5)

v5 adds `rails_get_provider_context`, which reads context from declared external MCP services. This changes the security model because a project file (the registry manifest) can name a network endpoint. The following controls are in place:

### Disabled by default

`config.context_providers.enabled` defaults to `false`. No DNS lookup or network request occurs unless the host explicitly enables providers and configures an allowlist. The tool returns a setup message and makes no network call when disabled.

### Exact host allowlist

`config.context_providers.allowed_hosts` is an exact-match list (case-insensitive, one trailing dot removed). No wildcard, suffix, or subdomain matching. Remote HTTPS endpoints must use the default port 443; non-default HTTPS ports are only permitted for loopback addresses on ports from `allowed_loopback_ports` (default: `[3000, 9292]`). Plain HTTP is allowed only for loopback endpoints on a port from `allowed_loopback_ports` or private endpoints when `allow_private_networks` is enabled.

### SSRF protection

`Registry::EndpointPolicy` validates every address returned by DNS resolution before connection. Private addresses (RFC1918, IPv6 ULA), link-local, multicast, unspecified, and cloud-metadata endpoints (`169.254.169.254`) are rejected. DNS answers fail closed: when any resolved address is blocked, the whole endpoint is rejected — a mix of permitted and blocked answers never results in a connection. The `allow_private_networks` override is development-only; when `Rails.env.production?` is true, private destinations are rejected even if `allow_private_networks` is set to `true`. Link-local and metadata addresses are never permitted.

Per-request connect/read timeouts are applied to the underlying HTTP transport from `timeout_seconds` (see the resource-limits table below). Connections are pinned to the first policy-validated address through a custom Faraday adapter (`Registry::PinningHttpAdapter`), so DNS rebinding cannot route provider calls or Doctor probes to an unapproved address. The adapter preserves the original Host header and TLS SNI while connecting to the approved IP.

### Read-only tool enforcement

Only remote tools that advertise `read_only_hint: true` and `destructive_hint: false` in their MCP tool metadata can be called. Missing or conflicting annotations are rejected.

### Credential safety

- Provider manifests never contain tokens.
- Auth headers come from a trusted `auth_resolver` lambda, bound to the provider's canonical endpoint.
- Headers are never logged, persisted, or copied into generated context.
- Reflected `Authorization` values in provider content are redacted to `[redacted]` before MCP responses are returned.
- Error messages are sanitized through `MessageSanitizer` — no URLs, file paths, or credential values leak into error results.

### Resource limits

| Limit | Default | Purpose |
|-------|---------|---------|
| `timeout_seconds` | 10 | Per-tool connect/read timeout |
| `aggregation_budget_seconds` | 30 | Total budget across all providers in one call |
| `max_response_bytes` | 1,048,576 (1 MiB) | Per-provider response cap before normalization |
| `max_providers` | 8 | Maximum providers per invocation |
| `max_tools_per_provider` | 16 | Maximum tools per provider |

### Cache exclusion

`rails_get_provider_context` is listed in `ToolResultCache::NON_CACHEABLE` so provider context always reflects live state, even when `tool_result_cache_ttl` is positive.

### Emergency shutdown

To immediately disable all provider traffic:

```ruby
RailsAiBridge.configure { |c| c.context_providers.enabled = false }
```

Or remove the `allowed_hosts` array — no host matches, all provider calls fail before DNS.

## Data-access tools: rails_query and rails_read_logs

Two built-in tools reach beyond static introspection: `rails_query` (database reads) and
`rails_read_logs` (log files). Both are **opt-in and disabled by default**
(`config.enable_data_tools = false`) and follow the same boundary: allowlist first, cap
everything, redact output.

### Opt-in registration

The two data-access tools are only registered with the MCP server when
`config.enable_data_tools = true`. The default (`false`) keeps them out of
`Server#tool_classes`, so an upgrade never silently starts exposing database rows or log
files to AI clients. `config.excluded_models` / `excluded_tables` do **not** restrict
`rails_query` — it runs on the app's database connection and can read any table the
database user can `SELECT` from. Enabling the flag means accepting that exclusion bypass;
treat the MCP endpoint with production-grade authentication when the flag is on.

### rails_query — SELECT-only SQL

| Mitigation | Detail |
|------------|--------|
| SELECT-only allowlist | The statement must start with `SELECT`. `INSERT`, `UPDATE`, `DELETE`, `ALTER`, `CREATE`, `DROP`, `TRUNCATE`, `REPLACE`, `PRAGMA`, `ATTACH`, and transaction control verbs are rejected. |
| CTEs rejected in v1 | `WITH` queries are rejected because mutating CTEs (wCTEs) allow writes inside a `WITH` clause; dialect-safe wCTE detection is error-prone. Rewrite as a plain `SELECT`. |
| Single statement | Any inner semicolon is rejected — conservatively, including semicolons inside string literals. |
| No locking, no DDL side effects | `FOR UPDATE` / `FOR SHARE` / `LOCK IN SHARE MODE` row locks and `SELECT ... INTO` (including MySQL `INTO OUTFILE`/`DUMPFILE`) are rejected by keyword guard. |
| Row cap | At most 100 rows are returned (`MAX_ROWS`), with a `truncated` flag when more matched. |
| Read-only transaction (PostgreSQL) | On PostgreSQL the statement runs inside a transaction with `SET TRANSACTION READ ONLY` plus `SET LOCAL statement_timeout = 5000`. The database itself rejects any write the keyword guard might miss. On other adapters (SQLite, MySQL, …) the keyword guard is **best-effort only** — no read-only transaction is enforced; rely on a least-privilege database user for defense in depth. |
| Statement timeout | On PostgreSQL, `statement_timeout` (5s). On other adapters, Ruby's `Timeout.timeout` (5s). Note that `Timeout.timeout` can leave a pooled connection in an uncertain state on non-PostgreSQL adapters when it interrupts a driver call mid-flight; this is a documented residual risk, mitigated by the short cap and the connection being returned to the pool. |
| Credential redaction | Values under credential-like columns (`password`, `passwd`, `secret`, `token`, `api_key`, `apikey`, `auth` — including `password_digest`, `encrypted_password`, `secret_access_key`) are replaced with `[redacted]` before the response leaves the process. This is **best-effort**: column aliases (`SELECT password AS harmless_name`) bypass column-name matching, and values in non-credential-named columns are not inspected. Redaction is a mitigation, not a guarantee — opt-in plus least-privilege DB access remain the primary controls. |
| Existing connection only | Queries run on the app's established `ApplicationRecord` connection; the bridge never opens its own database connection. |
| Error contract | Failures return `{"error": message}`; messages are sanitized so raw SQL fragments or driver errors do not leak connection details. |
| Server-side file reads (PostgreSQL) | The keyword guard cannot block functions: `SELECT pg_read_file(...)`, `pg_ls_dir`, or `lo_export` pass the SELECT-only check. These require superuser or `pg_read_server_files`/`pg_write_server_files`/`pg_execute_server_program` role membership, so the mitigation is operational — run the app on a least-privilege database role, which production apps should already do. |

### rails_read_logs — log tail with path allowlist

| Mitigation | Detail |
|------------|--------|
| Path allowlist | Only paths under `Rails.root/log` resolve. The check expands `..` segments and follows symlinks, then verifies a directory-prefix match, so `../`, absolute paths, and dot-segment tricks are all rejected. |
| Line cap | At most 400 lines are returned (`MAX_LINES`); detail levels default to 50 (`standard`) or 400 (`full`). |
| Byte cap | Each returned line is capped at 2000 bytes. |
| Credential redaction | Every returned line passes through `Registry::MessageSanitizer` (bearer headers, `token=`/`password=` pairs, URLs). |
| Error contract | Missing files return `{"error": "log file not found: ..."}` — no filesystem structure leaks beyond the requested name. |

Both tools inherit the general read-only guarantee (`read_only_hint: true`,
`destructive_hint: false`, `idempotent_hint: true`) and the same exposure advice as the
other tools: prefer stdio, or bind the HTTP endpoint to loopback with authentication.
Residual risks to accept before enabling: the keyword guard is best-effort on
non-PostgreSQL adapters; redaction is best-effort (aliases bypass it); and
`rails_query` bypasses MCP introspection exclusions by design.

## Residual risk checklist (operators)

Use this before exposing HTTP MCP beyond a single-developer machine:

| Risk | Default | Mitigation |
|------|---------|------------|
| Unauthenticated HTTP when no token/resolver/JWT is configured | Open access (local DX) | Set `RAILS_AI_BRIDGE_MCP_TOKEN` or `config.http_mcp_token`, and/or `config.require_http_auth = true` |
| `cors_origins` includes `*` | CORS disabled unless configured | Prefer exact origins; never combine `*` with browsers on untrusted networks |
| In-memory rate limit | Per-process only | Use `config.mcp.rate_limiter` / reverse proxy / WAF for multi-worker or multi-host |
| Information disclosure via tools | Read-only tools still reveal schema/routes/code | Prefer stdio; bind HTTP to `127.0.0.1`; use exclusions/presets for regulated data |
| `rails_query` / `rails_read_logs` read live data and bypass introspection exclusions | Opt-in, disabled by default | Keep `config.enable_data_tools = false` unless needed; when enabled, use a least-privilege DB user and production authentication |
| HTTP MCP request outcomes not logged | `http_log_json` defaults to false | Set `config.mcp.http_log_json = true`; `rails ai:doctor` warns when `auto_mount` is on and this is still off |
| Outbound provider calls to external services | Disabled by default | Enable only with exact `allowed_hosts`; use `allow_private_networks = false` (default) in production |

See also [SECURITY.md](../SECURITY.md) for production `auto_mount` requirements and private vulnerability reporting.
