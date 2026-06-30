# MCP HTTP security notes

Operational guidance for hosts using rails-ai-bridge MCP over HTTP.

## Treat the MCP token like a production secret

A valid Bearer token (or JWT accepted by your decoder) grants access to read-only tools that expose schema, routes, source layout, selected file contents via tools, and static MCP resources. Store tokens in encrypted credentials or a secrets manager; do not commit them to git.

## Prefer authentication on any network-exposed HTTP endpoint

By default, HTTP MCP allows anonymous access when no auth strategy is configured (backward compatible for local development). For servers reachable beyond localhost, set `config.mcp.require_http_auth = true` so unconfigured deployments return `401`, or configure `http_mcp_token`, `mcp_token_resolver`, or `mcp_jwt_decoder`. In production, also use `validate_http_mcp_server_in_production!` / `require_auth_in_production` as documented in the main README.

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
