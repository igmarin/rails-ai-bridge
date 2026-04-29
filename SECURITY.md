# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 3.0.x   | :white_check_mark: |
| 2.x     | :white_check_mark: |
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

This fork is maintained by **Ismael Marin**. If you discover a security vulnerability in `rails-ai-bridge`,
please report it responsibly:

1. **Do NOT open a public GitHub issue.**
2. Email **<ismael.marin@gmail.com>** with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
3. Include the affected version, Ruby version, Rails version, and whether the issue
   requires the HTTP transport or `auto_mount`.
4. You will receive a best-effort response as quickly as possible.

## Security Design

- All MCP tools are **read-only** and never modify your application or database.
- Code search (`rails_search_code`) uses `Open3.capture2` with array arguments to prevent shell injection.
- File paths are validated against path traversal attacks, and invalid regex input
  now returns a controlled tool response in the Ruby fallback path.
- Search is limited to an **allowlisted set of file extensions** by default;
  arbitrary extensions (e.g. `key`, `pem`, `env`) are rejected. See
  `config.search_code_allowed_file_types` to extend the list.
- `rails_search_code` caps **pattern length** (`config.search_code_pattern_max_bytes`,
  default 2048) and applies an optional **wall-clock timeout** per invocation
  (`config.search_code_timeout_seconds`, default 5; `0` disables).
- Credential **values** are never exposed. Top-level **key names** from encrypted
  credentials are omitted from introspection and the `rails://config` resource by
  default; set `config.expose_credentials_key_names = true` only if you accept
  that metadata exposure.
- The gem does not make any outbound network requests.
- The main risk is **information exposure**, not mutation: schema names, routes,
  controller structure, and code excerpts may still be sensitive in some environments.

## HTTP MCP authentication

For day-to-day hardening (tokens, `require_http_auth`, proxies, stdio threat model),
see **[docs/mcp-security.md](docs/mcp-security.md)**.

- **Shared secret:** set `config.http_mcp_token` and/or
  `ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]` (**ENV overrides** the config value when set).
  Clients send `Authorization: Bearer <token>`.
- **Custom resolver / JWT:** configure `config.mcp_token_resolver` or
  `config.mcp_jwt_decoder` (see [docs/GUIDE.md](docs/GUIDE.md)); clients still use a
  Bearer header; the gem does not ship a JWT library — you verify and decode inside
  your lambda.
- **Rack env context:** after a successful auth,
  `env["rails_ai_bridge.mcp.context"]` may contain **PII or claims**
  (e.g. JWT payload). Do not dump full Rack `env` to logs or APM; treat this key
  like session-derived data.
- When **no** auth mechanism is configured, HTTP MCP is **unauthenticated**
  (backward compatible for local use); configure one of the above before
  exposing the port beyond localhost.
- **`require_http_auth`:** set `config.require_http_auth = true`
  (or `config.mcp.require_http_auth = true`) so HTTP MCP returns **401** when
  no auth strategy is configured — useful when the bind address is not
  strictly localhost.
- **Rate limiting:** optional `config.mcp.rate_limit_max_requests` is an
  **in-memory, per-process** sliding window keyed by client IP (`request.ip`).
  It is **not** shared across Puma workers or hosts. Treat this as a light guard —
  use a reverse proxy, WAF, or `rack-attack` for strict distributed quotas.
- **MCP HTTP JSON logs:** when `config.mcp.http_log_json` is enabled, log lines
  include `client_ip` and path; treat log sinks like any operational data store
  (retention, access control).

## Production

- `config.auto_mount = true` in **production** raises at boot unless **both**
  `config.allow_auto_mount_in_production = true` and an MCP auth mechanism is
  configured (shared token, `mcp_token_resolver`, or `mcp_jwt_decoder`).
- `rails ai:serve_http` in **production** requires an auth mechanism
  (not necessarily a static shared secret).

## Operational Security Guidance

- Prefer **stdio** transport for local development and AI-assisted editing.
- If you enable HTTP transport, keep it bound to `127.0.0.1` unless you add your
  own network isolation and authentication controls.
- Do **not** expose `auto_mount` on public or shared production surfaces without an explicit threat model review.
- Treat generated files such as `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, and
  `.ai-context.json` as internal engineering documentation.

## Presets, exclusions, and MCP

`rails_get_schema`, `rails_get_model_details`, and other tools build on the same
introspection pipeline as `rails ai:bridge`. When you use `config.excluded_tables`,
`config.excluded_models`, `config.disabled_introspection_categories`, or presets
such as `:regulated`, treat the HTTP/stdio MCP surface with the **same
data-classification assumptions** as your committed context files: the tools remain
read-only but can still reveal structure you chose to omit from markdown.
