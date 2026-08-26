# Upgrading rails-ai-bridge

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
2. Enable and allowlist them in the initializer:

```ruby
RailsAiBridge.configure do |config|
  config.context_providers.enabled = true
  config.context_providers.allowed_hosts = ['context.example.com']
  config.context_providers.auth_resolver = lambda do |_endpoint, canonical_uri|
    # `token_for` is a placeholder — replace it with a real secret-manager call.
    # The README's "Provider auth" section shows worked Vault/ENV/KMS examples.
    { 'Authorization' => "Bearer #{token_for(canonical_uri.host)}" }
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
  Removing `allowed_hosts` is the emergency shutdown.

---

## Upgrading Rubydex to 0.4.0 (age-gated: mergeable Aug 28)

**Current:** `rubydex ~> 0.3.0` (installed: 0.3.0)
**Target:** `rubydex ~> 0.4.0`

### What changed in Rubydex 0.4.0

Source: [v0.3.0...v0.4.0](https://github.com/Shopify/rubydex/compare/v0.3.0...v0.4.0)

**Breaking changes:**
- **`Config` is now a proper object** (#965) — `Rubydex::Graph.new` may accept
  or require a `Config` instance instead of being constructed with no args.
  The adapter currently calls `Rubydex::Graph.new` with no arguments in
  `Indexer.build_index`; this may need updating.
- **Cypher query results return graph objects** (#873) — query return types
  may have changed from plain arrays/hashes to graph object wrappers.
- **Declaration core extracted** (#944) — declaration object shape may have
  changed; the serializer relies on `decl.name`, `decl.unqualified_name`,
  `decl.definitions`, `decl.ancestors`, `decl.descendants`, `decl.owner`,
  and `decl.class.name`.
- **`NamespaceStore` extracted** (#945) — namespace resolution internals
  changed; may affect `graph[name]` lookups.

**Enhancements:**
- Eagerly compute name depths into `Name` (#948)
- Remove Mixin vec clones from ancestor linearization (#949)
- Add linter configuration and configurable Rubydex linter (#972, #974)
- Add severity and related information to diagnostics (#973)
- Index RBS attribute methods (#970)

**Bug fixes:**
- Enqueue retry if `Object` ancestors are incomplete (#950)
- Visit `module_function` bodies once in `OperationBuilder` (#994)
- Fix `extend self` in anonymous modules (#1001)
- Linearize ancestors for implicitly created namespaces (#1005)

### Rubydex migration steps

1. **Update the gemspec constraint** from `~> 0.3.0` to `~> 0.4.0` (after Aug 28).
2. **Run `bundle update rubydex`** and verify the installed version is 0.4.x.
3. **Check `Rubydex::Graph.new`** — if `Config` is now required, update
   `Indexer.build_index` to construct and pass a `Config` object.
4. **Run characterization specs** under
   `spec/lib/rails_ai_bridge/rubydex_adapter/characterization_spec.rb` —
   these pin the graph API surface (method names, return shapes) and will
   fail if any breaking changes affect the adapter.
5. **Verify declaration/definition shapes** — the serializer's
   `declaration_type` method uses `decl.class.name` pattern matching
   (`/class/`, `/module/`, `/method/`, `/constant/`). If class names change
   in 0.4.0, update `TYPE_PATTERNS` in `serializer.rb`.
6. **Test incremental reindex** — the `IncrementalIndexer` calls
   `graph.delete_document`, `graph.index_source`, `graph.document`, and
   `graph.resolve`. Verify these methods still exist with the same signatures.
7. **Smoke-test `rails_search_semantic` tool** — this is the primary
   user-facing consumer of the Rubydex adapter.

### Rubydex characterization specs

The following spec files pin current behavior to catch regressions:
- `spec/lib/rails_ai_bridge/rubydex_adapter/characterization_spec.rb` —
  full graph API contract (indexing, search, declarations, definitions,
  references, locations, ancestors/descendants, graceful failure)
- `spec/lib/rails_ai_bridge/rubydex_adapter_spec.rb` — adapter unit tests
- `spec/lib/rails_ai_bridge/rubydex_adapter/incremental_indexer_spec.rb` —
  incremental rebuild and persistence behavior
- `spec/lib/rails_ai_bridge/rubydex_adapter/serializer_spec.rb` —
  declaration/definition serialization shapes
- `spec/lib/rails_ai_bridge/rubydex_adapter/indexer_spec.rb` —
  file discovery and graph construction
- `spec/lib/rails_ai_bridge/rubydex_adapter/method_counter_spec.rb` —
  method counting logic

---

## Upgrading MCP SDK to 1.3.0 (age-gated: mergeable Aug 29)

**Current:** `mcp >= 1.0, < 2.0` (installed: 1.3.0)
**Target:** `mcp >= 1.3, < 2.0`

The installed version is already 1.3.0; the gemspec lower bound needs
tightening from `>= 1.0` to `>= 1.3` to ensure all hosts pick up the
1.2.0+ stateless lifecycle and 1.3.0 resource list handler features.

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

### MCP migration steps

1. **Update the gemspec constraint** from `>= 1.0, < 2.0` to `>= 1.3, < 2.0`
   (after Aug 29).
2. **Run `bundle update mcp`** — most hosts already resolve 1.3.0; this
   tightens the floor.
3. **Run characterization specs** under `spec/lib/rails_ai_bridge/mcp/`:
   - `protocol_characterization_spec.rb` — SDK version, server constructor,
     transport classes, 2026-07-28 lifecycle method surface
   - `tool_annotations_spec.rb` — all 19 tool annotation hints
   - `resource_lists_spec.rb` — resource/template construction and read handler
   - `error_responses_spec.rb` — 404/401/403/429 error shapes, response bounds
4. **Verify `resources_list_handler`** — new in 1.3.0. If the bridge wants
   context-dependent resource lists, register a handler via
   `server.resources_list_handler { |params| ... }`.
5. **Check for duplicate request id rejection** — 1.3.0 rejects duplicate
   in-flight JSON-RPC request ids (#521). This is a server-side change that
   should be transparent to the bridge, but verify no test relies on
   duplicate ids being accepted.
6. **Verify exception message masking** — 1.2.0 stopped leaking exception
   messages to clients via JSON-RPC error data (#486). Ensure error
   responses still contain useful information for debugging.
7. **Smoke-test stdio and HTTP transports** — start `rails ai:serve` and
   verify tool calls and resource reads work end-to-end.

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
