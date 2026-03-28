# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| unreleased fork | :white_check_mark: |
| 0.7.x   | :white_check_mark: |
| 0.6.x   | :white_check_mark: |
| < 0.6   | :x:                |

## Reporting a Vulnerability

This fork is maintained by **Ismael Marin**. If you discover a security vulnerability in this fork of `rails-ai-bridge`, please report it responsibly:

1. **Do NOT open a public GitHub issue.**
2. Email **ismael.marin@gmail.com** with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
3. Include the affected version, Ruby version, Rails version, and whether the issue requires the HTTP transport or `auto_mount`.
4. You will receive a best-effort response as quickly as possible.

## Security Design

- All MCP tools are **read-only** and never modify your application or database.
- Code search (`rails_search_code`) uses `Open3.capture2` with array arguments to prevent shell injection.
- File paths are validated against path traversal attacks, and invalid regex input now returns a controlled tool response in the Ruby fallback path.
- Search is limited to an **allowlisted set of file extensions** by default; arbitrary extensions (e.g. `key`, `pem`, `env`) are rejected. See `config.search_code_allowed_file_types` to extend the list.
- Credential **values** are never exposed. Top-level **key names** from encrypted credentials are omitted from introspection and the `rails://config` resource by default; set `config.expose_credentials_key_names = true` only if you accept that metadata exposure.
- The gem does not make any outbound network requests.
- The main risk is **information exposure**, not mutation: schema names, routes, controller structure, and code excerpts may still be sensitive in some environments.

## HTTP MCP authentication

- **Shared secret:** set `config.http_mcp_token` and/or `ENV["RAILS_AI_BRIDGE_MCP_TOKEN"]` (**ENV overrides** the config value when set). Clients send `Authorization: Bearer <token>`.
- **Custom resolver / JWT:** you can instead configure `config.mcp.auth.token_resolver` or `config.mcp.auth.jwt_decoder` (see [docs/GUIDE.md](docs/GUIDE.md)); clients still use a Bearer header; the gem does not ship a JWT library—you verify and decode inside your lambda.
- **Rack env context:** after a successful auth, `env["rails_ai_bridge.mcp.context"]` may contain **PII or claims** (e.g. JWT payload). Do not dump full Rack `env` to logs or APM; treat this key like session-derived data.
- When **no** auth mechanism is configured, HTTP MCP is **unauthenticated** (backward compatible for local use); configure one of the above before exposing the port beyond localhost.
- **Misconfiguration:** setting `strategy` to `:bearer_token` without a `token_resolver` and without a static MCP token causes **boot failure** (`ConfigurationError`) so the endpoint cannot start in an accidentally open state.
- **Rate limiting:** optional `config.mcp.rate_limit_max_requests` is an **in-memory, per-process** sliding window keyed by client IP (as seen by `request.ip`). It is **not** shared across Puma workers or hosts. Empty per-IP buckets are dropped after timestamps expire to avoid unbounded growth from **idle** IPs; an attacker can still force **many distinct IPs within the window** (or spoof forwarded IPs if proxies are misconfigured), so treat this as a light guard—use a reverse proxy, WAF, or `rack-attack` for strict quotas.

## Production

- `config.auto_mount = true` in **production** raises at boot unless **both** `config.allow_auto_mount_in_production = true` and an MCP auth mechanism is configured (shared token, `token_resolver`, or `jwt_decoder`).
- `rails ai:serve_http` in **production** requires the same class of auth configuration (not necessarily a static shared secret).

## Operational Security Guidance

- Prefer **stdio** transport for local development and AI-assisted editing.
- If you enable HTTP transport, keep it bound to `127.0.0.1` unless you add your own network isolation and authentication controls.
- Do **not** expose `auto_mount` on public or shared production surfaces without an explicit threat model review.
- Treat generated files such as `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, and `.ai-context.json` as internal engineering documentation.

## Copilot instructions file (`.github/copilot-instructions.md`)

Regeneration wraps **gem-managed** content in HTML comment markers. Content **outside** those markers is left untouched when the markers already exist. If you have an **older** repo file **without** markers, `rails ai:bridge` **skips** overwriting that file by default so manual guidance is not destroyed. To replace the entire file from generated output, set:

`RAILS_AI_BRIDGE_COPILOT_MERGE=overwrite`

To skip writing Copilot instructions when you would otherwise overwrite:

`RAILS_AI_BRIDGE_COPILOT_MERGE=skip`

## Presets, exclusions, and MCP

`rails_get_schema`, `rails_get_model_details`, and other tools build on the same introspection pipeline as `rails ai:bridge`. When you use **`config.excluded_tables`**, **`config.excluded_models`**, **`config.disabled_introspection_categories`**, or presets such as **`:regulated`**, treat the HTTP/stdio MCP surface with the **same data-classification assumptions** as your committed context files: the tools remain read-only but can still reveal structure you chose to omit from markdown.
