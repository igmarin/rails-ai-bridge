# Upgrading rails-ai-bridge

## Upgrading from 5.0.0 to 5.1.0

**One action required if you are pinned to `rubydex` 0.3.x:**

The `rubydex` gem constraint moved from `~> 0.3.0` to `~> 0.4.0`. After upgrading
rails-ai-bridge, update the lockfile:

```bash
bundle update rails-ai-bridge rubydex
```

`Rubydex::Graph.new` with no arguments still works on 0.4.1; no application or
initializer changes are required. Semantic search (`rails_search_semantic`)
is unchanged.

The official MCP SDK range remains `>= 1.3, < 2.0`. This release was tested
with mcp 1.5.1 (HTTP client JSON parse fix for json 3.0). Hosts already on
any 1.3–1.5.x need no extra step.

### Rolling back

Pin `gem 'rails-ai-bridge', '~> 5.0.0'` and `bundle update rails-ai-bridge
--conservative`. If you already updated rubydex to 0.4.x, pin
`gem 'rubydex', '~> 0.3.0'` only if you also stay on rails-ai-bridge 5.0.x.

---

## Upgrading from 4.3.0 to 5.0.0

**No application-code or configuration changes are required to upgrade.** v5 is intentionally
backwards-compatible by default: outbound context providers are disabled,
`rails_get_context` stays in-process, and all v4 configuration settings still
work.

Run:

```bash
bundle update rails-ai-bridge
```

Bundler will pull in the new dependency floor (`mcp >= 1.3`, `faraday >= 2.0`,
`event_stream_parser >= 1.0`) automatically.

### What changed in v5

1. **Outbound context providers (opt-in, disabled by default)** —
   `rails_get_provider_context` can fetch context from external MCP services
   declared in your registry manifest. No network request is made unless you
   explicitly enable and allowlist providers. See
   [docs/v5/context-providers-design.md](docs/v5/context-providers-design.md).
2. **AppScope runtime seam** — `RailsAiBridge::AppScope.with_app(app) { ... }`
   and `RailsAiBridge::AppScope.current_app` let standalone callers, tests, and
   the install generator scope a different app without hardcoding
   `Rails.application`.
3. **BootManager and StaticApp** — `RailsAiBridge::BootManager` gives the Doctor
   and standalone callers a bounded, structured boot-to-static-fallback path.
   `RailsAiBridge::StaticApp` supports static-only introspection without booting
   Rails.
4. **Doctor network probe** — `rails ai:doctor` and `rails ai:check` can probe
   declared provider endpoints with `NETWORK=1`. Ordinary runs still make no
   network calls.
5. **`mcp` dependency floor raised to 1.3** — required for `MCP::Client::HTTP`.
   `faraday` and `event_stream_parser` are now explicit gem dependencies.

### To start using outbound providers

1. Declare providers and read-only tools in
   `config/rails_ai_bridge/registry.json`.
1. Enable and allowlist them in the initializer:

   ```ruby
   RailsAiBridge.configure do |config|
     config.context_providers.enabled = true
     config.context_providers.allowed_hosts = ['context.example.com']
     config.context_providers.auth_resolver = lambda do |_endpoint, canonical_uri|
     # Set this in your environment, or replace with a real secret-manager call.
     # The README's "Provider auth" section shows worked Vault/ENV/KMS examples.
     token = ENV.fetch('MCP_PROVIDER_TOKEN')
     { 'Authorization' => "Bearer #{token}" }
     end
   end
   ```

1. Call `rails_get_provider_context` from your AI client, or run
   `NETWORK=1 rails ai:doctor` to verify reachability.

### Production guard for private networks

In production, `config.context_providers.allow_private_networks` has no effect;
private (RFC1918/ULA) destinations are rejected, even if the allowlist would
otherwise permit them. Keep provider endpoints on public or explicitly allowed
loopback addresses.

### Verification

```bash
rails ai:doctor        # no network
NETWORK=1 rails ai:doctor  # with provider probes
```

### Rolling back

- **Pin to v4** — set `gem 'rails-ai-bridge', '~> 4.3.0'` in the host `Gemfile`,
  then `bundle update rails-ai-bridge --conservative`.
- **Runtime disable** — set `config.context_providers.enabled = false` in the
  initializer to stop outbound requests without changing the installed version.
  This is the complete emergency shutdown. Clearing `allowed_hosts` alone is
  **not** sufficient: loopback endpoints on allowed ports (for example,
  `localhost:3000` or `localhost:9292`) remain reachable because loopback policy
  is independent of the host allowlist.

---

## MCP SDK 1.3 floor (historical — shipped in 5.0.0)

This age-gated note is obsolete. v5.0.0 already raised the gemspec to
`mcp >= 1.3, < 2.0`. v5.1.0 keeps that range and was tested with mcp 1.5.1.
Hosts on any 1.3–1.5.x need no extra MCP step. The 1.1 → 1.3 changelog below
is kept as background only.

### What changed in MCP 1.1.0 → 1.2.0 → 1.3.0

Source: [CHANGELOG.md](https://github.com/modelcontextprotocol/ruby-sdk/blob/main/CHANGELOG.md)

**1.3.0 (Aug 22, 2026):**

- **Added:** `resources_list_handler` for context-dependent resource lists (#509)
- **Added:** Handler-returned `_meta` passed through subscribe result (#510)
- **Changed:** Bound OAuth response bodies in the client (#520)
- **Changed:** Reject duplicate in-flight JSON-RPC request ids (#521)
- **Changed:** Documentation moved from README.md to documentation site (#523)

**1.2.0 (Aug 15, 2026) — 2026-07-28 stateless lifecycle:**

- **Added:** SEP-2575 modern request envelope handling (#475)
- **Added:** Both lifecycle eras over stdio with era lock (#478)
- **Added:** Sessionless modern path over Streamable HTTP (#479)
- **Added:** `server/discover` and client modern lifecycle (#480)
- **Added:** Multi round-trip `input_required` results (#481, #500, #501)
- **Added:** `MCP::Elicitation::EnumSchema` builders (#482)
- **Added:** Modern lifecycle admission rules (#489)
- **Added:** `subscriptions/listen` notification stream (#495)
- **Added:** Opt-in `requestState` sealing via `MCP::Server::RequestStateSecurity` (#496)
- **Added:** `x-mcp-header` tool parameters mirrored to `Mcp-Param-*` headers (#498)
- **Added:** Cache hints on modern cacheable results (#499)
- **Changed:** `Mcp-Method` header required on modern path (#492)
- **Changed:** Server-to-client requests refused in modern lifecycle (#503)
- **Changed:** SSE reconnection wait bounded (#504)
- **Changed:** Automatic pagination bounded in client (#505)
- **Deprecated:** Roots and Sampling capabilities deprecated per SEP-2577 (#516)
- **Fixed:** Exception messages no longer leaked to clients (#486)
- **Fixed:** Invalid Params for unknown prompts and missing prompt arguments (#517)

**1.1.0 (Aug 1, 2026):**

- **Added:** 2026-07-28 as Latest Protocol Version (#476)
- **Added:** Server tool annotations exposed on `MCP::Client::Tool` (#445)
- **Fixed:** Explicit tool response content preserved (#469)

### MCP characterization specs

The following spec files pin current protocol behavior:

- `spec/lib/rails_ai_bridge/mcp/protocol_characterization_spec.rb` —
  SDK version, server construction, transport routing, lifecycle methods
- `spec/lib/rails_ai_bridge/mcp/tool_annotations_spec.rb` —
  all 19 tool annotations, response construction, truncation bounds
- `spec/lib/rails_ai_bridge/mcp/resource_lists_spec.rb` —
  resource/template construction, read handler, URI resolution
- `spec/lib/rails_ai_bridge/mcp/error_responses_spec.rb` —
  HTTP error responses (404/401/403/429), CORS preflight, response bounds
- `spec/lib/rails_ai_bridge/mcp/sdk_compatibility_spec.rb` —
  basic SDK surface compatibility (pre-existing)

---

## Upgrading from 3.7.x to 4.0.0 (`mcp` 1.x) (#104/#118)

**Action required:**

```bash
bundle update mcp rails-ai-bridge
```

The official MCP Ruby SDK major is **1.x** (gemspec `mcp >= 1.0, < 2.0`; was
`>= 0.25, < 1.0`). Hosts previously resolving `mcp` 0.25.x must pick up **1.1+**
via Bundler. Rails-ai-bridge production code did not need API adapters for
1.1.0, but you should smoke-test MCP stdio/HTTP after upgrading.

Optional: characterization coverage lives in
`spec/lib/rails_ai_bridge/mcp/sdk_compatibility_spec.rb` (for contributors).

---

## Upgrading from 3.6.1 to 3.6.2

**No configuration changes required.**

If your app uses `config.active_record.schema_format = :sql`, offline schema
introspection and `rails ai:doctor` now use `db/structure.sql` automatically
(no need for `db/schema.rb`). Live DB introspection was already format-agnostic.

---

## Upgrading from 3.6.0 to 3.6.1

**One action required if you are pinned to `rubydex` 0.2.x:**

The `rubydex` gem constraint moved from `~> 0.2.9` to `~> 0.3.0`. After upgrading
rails-ai-bridge:

```bash
bundle update rubydex
```

No configuration or application code changes are required for the security and
documentation updates in 3.6.1. Skill-pack git sources must use `https://`,
SCP-style `git@host:path`, or `ssh://` (plain `http://` and `file://` are rejected).

---

## Upgrading from 3.5.x to 3.6.0

**One action required if you are pinned to an older `rubydex`:**

The `rubydex` gem constraint was tightened from `~> 0.2.4` to `~> 0.2.9`. If your
lockfile resolves to rubydex 0.2.4–0.2.8, update it after upgrading:

```bash
bundle update rubydex
```

No other configuration or code changes are required. The `mcp` lower bound also
moved from `>= 0.10` to `>= 0.25`, but if you were already on a recent version
(no earlier than 0.25) this is a no-op.

---

## Upgrading from 1.x to 2.x

**No configuration changes required.** Every `config.*` attribute from 1.x is still available — `Configuration`
now delegates to focused sub-objects but exposes the same flat DSL. See `CHANGELOG.md` for the full list of
internal changes.

---

## New in 2.x — `config.mcp` settings

MCP HTTP operational configuration lives under `config.mcp` (a `Config::Mcp` object). All attributes are also
accessible as flat delegators on `config` directly.

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

When `rate_limit_max_requests` is `nil` (default), the gem may apply an **implicit** per-IP ceiling from
`security_profile` (`:strict` / `:balanced` / `:relaxed`), unless `mode` suppresses it:

- **`mode: :dev`** — no implicit limit.
- **`mode: :hybrid`** (default) — implicit limit only when `Rails.env.production?`.
- **`mode: :production`** — implicit limit in every Rails environment.

Set `config.mcp.rate_limit_max_requests = 0` to **disable** limiting entirely (including implicit).
A **positive integer** always overrides the profile.

> **Note:** the rate limiter is **in-memory and per-process**. It is not shared across Puma workers or hosts.
> Use a reverse proxy, WAF, or `rack-attack` for strict distributed quotas.

### Structured logging

```ruby
RailsAiBridge.configure do |config|
  # Emit one JSON line per MCP HTTP response to Rails.logger
  config.mcp.http_log_json = true
end
```

Each log line includes `msg`, `event`, `http_status`, `path`, `client_ip`, and `request_id` (when present).
Tokens and full Rack `env` are never logged. The flag is read **on each request** (unlike the rate-limit
snapshot taken at `HttpTransportApp.build`).

### Post-auth authorization (`authorize`)

```ruby
RailsAiBridge.configure do |config|
  # Called after successful auth; returning falsey yields HTTP 403
  config.mcp.authorize = ->(context, request) {
    context[:role] == "admin"
  }
end
```

The lambda is read and called **on every request** (like `http_log_json`), so changes take effect immediately
without rebuilding the transport app. If the lambda raises a `StandardError`, the gem treats it as a 403 and
logs the error — it does not propagate as a 500.

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

Rails **boot** raises `RailsAiBridge::ConfigurationError` if you configure `:bearer_token` strategy without a
resolver or static token — that combination would leave HTTP MCP unauthenticated.

---

## Resolver / JWT return values

Return **`nil`** (or `false`) when a token is invalid. Returning `false` explicitly is treated as auth failure (401).
