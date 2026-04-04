# MCP HTTP security notes

Operational guidance for hosts using rails-ai-bridge MCP over HTTP.

## Treat the MCP token like a production secret

A valid Bearer token (or JWT accepted by your decoder) grants access to read-only tools that expose schema, routes, source layout, selected file contents via tools, and static MCP resources. Store tokens in encrypted credentials or a secrets manager; do not commit them to git.

## Prefer authentication on any network-exposed HTTP endpoint

By default, HTTP MCP allows anonymous access when no auth strategy is configured (backward compatible for local development). For servers reachable beyond localhost, set `config.mcp.require_http_auth = true` so unconfigured deployments return `401`, or configure `http_mcp_token`, `mcp_token_resolver`, or `mcp_jwt_decoder`. In production, also use `validate_http_mcp_server_in_production!` / `require_auth_in_production` as documented in the main README.

## Rate limiting and proxies

Built-in rate limiting keys off the Rack request IP. Behind reverse proxies, configure Rails `trusted_proxies` so `request.ip` reflects the real client; otherwise limits may apply to the wrong address or be bypassed.

## Optional authorization after auth

`config.mcp.authorize` can return false to issue `403` for otherwise valid tokens (e.g. tenant or role checks).

## Stdio transport

The stdio MCP server has no Bearer layer; anyone who can run the process can use the tools. Use isolated users or containers if multiple tenants share a host.

## See also

- [SECURITY.md](../SECURITY.md) — reporting vulnerabilities and design summary
- [docs/GUIDE.md](GUIDE.md) — full configuration and MCP tool reference
