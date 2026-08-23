# Outbound context providers for v5

> **Status:** Accepted for implementation

## 1. Executive summary

rails-ai-bridge already reads local Rails context and exposes it through static files and tools that an AI client can call. v5 adds an optional way to read context from declared external Model Context Protocol (MCP) services. This changes the security model because a project file can name a network endpoint. Provider traffic will therefore be disabled by default, limited to an explicit host allowlist, and allowed to call only remote tools that advertise read-only, non-destructive behavior. Hosts must configure one `context_providers` section with an enable switch, exact host list, bounded limits, and an optional auth resolver.

## 2. Context and scope

The registry already models `ContextProviderDefinition` and `ContextToolSpec`, and `rails_list_context_providers` displays them. Nothing currently connects to the declared endpoint. The local `rails_get_context` tool is an in-process composite and must remain local.

This design adds:

- a policy that validates provider endpoints before every connection;
- a client adapter over the official MCP Ruby SDK HTTP client;
- an aggregator for simple and mapped tool results;
- `rails_get_provider_context` for explicit provider reads;
- an opt-in Doctor reachability check;
- configuration, limits, error behavior, and operational documentation.

The model dependency graph, Rails semantic validation, standalone CLI, and ArchSpec work are separate v5 tasks. They are not provider implementation details. The standalone executable is intentionally restored as a new v5 capability; it does not exist in v4. The release plan tracks those streams separately from this provider design.

It does not add an outbound client for arbitrary URLs, a background refresh loop, persistent provider sessions, or a second MCP protocol implementation.

## 3. System context

```text
registry.json
    |
    v
ContextProviderDefinition --> EndpointPolicy --> MCP::Client::HTTP
          |                                      |
          +--> ContextAggregator <---------------+
                         |
                         v
             rails_get_provider_context

RailsAiBridge local context --> rails_get_context
```

The registry describes which provider and tools may be used. Configuration decides whether network access is enabled and which hosts are trusted. The policy owns endpoint and network safety. The client owns MCP lifecycle and response normalization. The aggregator owns mapping, limits, memoization, and optional-provider failure handling. The MCP tool only validates input and presents the aggregate result.

## 4. Proposed design

### How it works

A host declares a provider and its read-only tools in `config/rails_ai_bridge/registry.json`. It separately enables providers and allowlists the exact host in the Rails initializer. An assistant calls `rails_get_provider_context(provider: "billing")`. The tool checks the global enable switch, loads the manifest, validates the provider endpoint, resolves its DNS addresses, and rejects the request if the endpoint is not allowed. The client opens one MCP HTTP session, performs the SDK handshake, lists tools, verifies the requested tools' annotations, calls each declared tool, bounds the response, closes the session, and returns normalized data. The aggregator maps each result to its declared field and reports optional failures without hiding required failures.

If providers are disabled, the tool returns a setup message and makes no DNS or network call. If the provider is optional and unavailable, local context remains usable.

### Components and responsibilities

**`Config::ContextProviders`** in `lib/rails_ai_bridge/config/context_providers.rb` owns the enable switch, limits, timeout, response cap, host allowlist, private-network override, and downstream-auth resolver. `Configuration` exposes it through `configuration.context_providers`; there are no flat delegators for secret or network settings. It does not parse MCP responses or perform I/O.

**`Registry::EndpointPolicy`** in `lib/rails_ai_bridge/registry/endpoint_policy.rb` owns URI canonicalization, scheme/host/port rules, DNS address checks, and redirect/peer validation. It uses Ruby standard-library `Resolv`, `IPAddr`, and `Addrinfo` through an injected resolver. It does not open a socket or store credentials.

**`Registry::ContextProviderClient`** in `lib/rails_ai_bridge/registry/context_provider_client.rb` owns one provider exchange through `MCP::Client::HTTP`. It receives policy and transport dependencies, verifies remote tool annotations, normalizes successful results, translates failures to safe typed errors, and closes the client in `ensure`. It must pass the policy's validated address set to a pinning-capable HTTP adapter. It does not decide whether a provider is optional or how fields are mapped.

**`Registry::ContextAggregator`** in `lib/rails_ai_bridge/registry/context_aggregator.rb` owns provider iteration, tool mapping, deterministic ordering, sequential execution, request-scope memoization, and resource budgets. It does not bypass endpoint policy or call a remote tool that the client rejected.

**`Registry::ProviderRequestScope`** in `lib/rails_ai_bridge/registry/provider_request_scope.rb` owns the per-invocation memo and its cleanup. It does not use process-global or cross-request state.

**`Registry::ContextProviderError`** in `lib/rails_ai_bridge/registry/context_provider_error.rb` owns the stable provider error hierarchy and safe categories. It does not expose SDK, Faraday, response-body, or credential details.

**`Tools::GetProviderContext`** in `lib/rails_ai_bridge/tools/get_provider_context.rb` owns MCP input validation and response formatting. It does not contain HTTP, DNS, or aggregation logic.

**`Doctor::Checkers::RegistryChecker`** owns structural checks by default. Its network check requires `network: true` and reuses the client probe path. It does not open sockets during an ordinary Doctor run.

### Decisions

**Use the official MCP SDK client.** MCP 1.3.0 provides `MCP::Client`, Streamable HTTP support, lifecycle negotiation, response bounds, and protocol error handling. A local JSON-RPC client or Req wrapper would duplicate protocol code and create another security surface. The v5 gemspec will require `mcp >= 1.3, < 2.0` and `faraday >= 2.0, < 3.0`; both dependencies are verified in the compatibility matrix before release.

**Disable providers everywhere by default.** A manifest is project data, not permission to make outbound requests. Hosts must enable providers and configure an allowlist. This is safer for CI, development, production, and standalone CLI use, and it makes accidental network access visible in configuration review.

**Use exact host allowlists.** The policy lowercases DNS names, removes one trailing dot, and compares the resulting ASCII host literally with an entry in `allowed_hosts`; it does not perform suffix, wildcard, or implicit subdomain matching. It does not treat a manifest URL or redirect destination as trusted. Remote HTTPS uses port 443. Loopback HTTP is allowed only when the loopback host is explicitly allowlisted; it is intended for local development. IDNA conversion, if accepted by the URI library, must produce the same canonical form before comparison.

**Reject private and metadata addresses by default.** Every address returned for a hostname is checked immediately before connection with `Resolv` and `IPAddr`. Private addresses are internal network ranges such as RFC1918 IPv4 (`10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`) and IPv6 unique-local (`fc00::/7`); loopback, link-local (`169.254.0.0/16` and `fe80::/10`), multicast, and unspecified ranges are also rejected except for the explicit allowlisted loopback case. Cloud metadata endpoints, including `169.254.169.254`, remain blocked. A clearly named development-only private-network override may allow private or link-local destinations, but never metadata addresses.

**Use resolver-provided headers for downstream auth.** Provider manifests never contain tokens. The resolver returns headers for a provider name at call time. Headers are not logged, persisted, or copied into generated context. The resolver is trusted application code; its contract requires returning headers only for the requested provider, and implementation tests assert that headers never appear in logs, generated context, or error messages. OAuth discovery and token acquisition are out of scope for v5; hosts can supply an already-issued bearer token through the resolver.

**Fetch sequentially and close each session.** Sequential calls make ordering, total budgets, failure handling, and shutdown predictable. A session is not retained between tool calls. Parallel fetching and retries are deferred until measurements show sequential calls are insufficient.

**Treat external data as external.** Provider results are never labeled `[VERIFIED]` merely because a remote server returned them. The formatted response includes provider identity and source status. The outer tool is read-only but not idempotent because provider data can change.

**Use two response limits.** MCP 1.3's 4 MiB message bound protects the SDK parser. rails-ai-bridge adds a 1 MiB provider-body cap before normalization and its existing `max_tool_response_chars` cap after formatting. The smaller bridge cap is intentional and is not a replacement for the SDK bound.

## 5. Invariants and requirements

### Invariants

- `INV-1`: No provider DNS lookup or network request occurs unless `context_providers.enabled` is true and the endpoint passes `EndpointPolicy`.
- `INV-2`: A remote tool is callable only when its MCP tool metadata advertises `read_only_hint: true` and `destructive_hint: false`; missing or conflicting metadata is rejected.
- `INV-3`: Every remote request has a connect/read timeout, a maximum response size, and a total aggregation budget.
- `INV-4`: Remote authentication values never come from the manifest and never appear in logs, exception messages, generated files, or MCP responses.
- `INV-5`: Redirects cannot leave the validated endpoint and are disabled by default.
- `INV-6`: `EndpointPolicy` returns a canonical URI and approved address set. The transport must connect to one of those addresses. If the selected Faraday adapter cannot accept the resolved address or expose the connected peer for verification, the client must use a pinning-capable adapter or reject the hostname endpoint; it must not fall back to DNS-only validation.
- `INV-7`: Ordinary Doctor runs do not open provider sockets. Reachability requires an explicit network option.
- `INV-8`: `rails_get_context` never calls a provider and retains its current local behavior.
- `INV-9`: An optional provider failure does not discard successful provider results; a required provider failure is visible as an error.
- `INV-10`: Every provider request closes its client and releases transport resources, including after an exception.

### Requirements

- `context_providers.enabled` defaults to `false`.
- The v4 gemspec currently permits MCP 1.x; Task 10 raises the v5 minimum to MCP 1.3 because the provider client depends on that SDK surface.
- The default per-tool timeout is 10 seconds.
- The MCP SDK's 4 MiB message limit is an outer parser guard. The bridge's default network response cap is 1 MiB before MCP tool truncation.
- Provider and tool counts have explicit finite caps.
- Provider and tool iteration order is deterministic.
- Tool responses preserve structured content when available and safely normalize unsupported content.
- Configuration errors are reported before network I/O.
- The client supports Streamable HTTP through the official SDK and does not send a request to a plain remote HTTP endpoint.
- Provider errors expose a stable category and safe message, not raw headers, URLs with credentials, or response bodies.

## 6. Interfaces and data

### Configuration

```ruby
RailsAiBridge.configure do |config|
  config.context_providers.enabled = true
  config.context_providers.allowed_hosts = ['context.example.com']
  config.context_providers.timeout_seconds = 10
  config.context_providers.max_response_bytes = 1_048_576
  config.context_providers.auth_resolver = lambda do |provider_name|
    { 'Authorization' => "Bearer #{token_for(provider_name)}" }
  end
end
```

The private-network override is a separate, explicitly named setting and defaults to false. The initializer template must include this warning: `Enabling allow_private_networks permits connections to internal network addresses; use it only for controlled development endpoints.` The static CLI configuration may contain enablement and allowlists but must not contain auth headers or token values. `Doctor.new(network: false)` is the default, and the value is passed to `RegistryChecker#call(network:)`; the checker never reads process-global environment state directly. The Rake task passes `network: ENV['NETWORK'] == '1'`, and the standalone CLI passes `network: true` only for `--network`.

The existing manifest shape remains the source of provider names, endpoints, optionality, and `ContextToolSpec` mappings. The manifest does not gain a secret field or an enable-by-presence rule.

### Client interface

```ruby
client = RailsAiBridge::Registry::ContextProviderClient.new(
  provider: provider_definition,
  policy: endpoint_policy,
  transport_factory: transport_factory,
  auth_resolver: auth_resolver
)
client.call_tool(tool_name, arguments: {})
```

The public result is a normalized hash containing provider name, tool name, content, and provenance. The error hierarchy is `RailsAiBridge::Registry::ContextProviderError < RailsAiBridge::Error`, with `PolicyError`, `AuthenticationError`, `ConnectionError`, `TimeoutError`, `ProtocolError`, `ResponseTooLargeError`, and `RemoteToolError` subclasses. The client exposes safe messages and a stable category; callers do not depend on Faraday or MCP exception classes.

### Aggregator interface

```ruby
aggregator = RailsAiBridge::Registry::ContextAggregator.new(...)
aggregator.fetch_all
aggregator.fetch_one('billing')
```

`fetch_all` returns provider-keyed mapped data. Simple tools use the tool name as the field. Mapped tools use the declared field and pass declared arguments. The aggregator memoizes within a `Registry::ProviderRequestScope` created for one MCP tool invocation. The scope is the same whether the call arrives over stdio or HTTP. It is not a process-wide cache, Rails controller request cache, or cross-request HTTP cache. The tool owns the scope lifetime and ensures it is discarded after the call.

### Tool interface

```text
rails_get_provider_context(provider: optional provider name)
```

Without `provider`, all declared providers are considered. With `provider`, only that provider is fetched. Disabled access, no manifest, an unknown provider, policy rejection, and required-provider failure receive distinct recovery text. The tool is annotated `read_only_hint: true`, `destructive_hint: false`, `idempotent_hint: false`, and `open_world_hint: true`.

## 7. Failure behavior and lifecycle

Manifest parsing and configuration validation happen before any DNS lookup. A policy failure is deterministic and non-retryable. Connection and timeout failures are bounded and are not retried in v5. An MCP protocol or remote-tool error is reported as a provider failure.

For `optional: true`, the aggregator records a bounded warning and continues. For required providers, it returns a typed aggregate failure with the provider name and category. Raw response bodies are not included in errors. A disabled provider returns immediately.

Each client call creates or receives one SDK transport, calls `connect`, performs the required tool lookup/call, and closes the transport in `ensure`. A failed boot, interrupted request, or client exception cannot leave the request scope or client session active.

Doctor's structural mode follows the existing lifecycle and never performs network I/O. Its explicit network mode uses a lightweight MCP lifecycle/tool-list probe through the same client adapter and applies the same policy, timeout, authentication, and response limits.

## 8. Security, privacy, and operations

The trust boundary is the registry manifest, initializer configuration, downstream provider, and provider response. The manifest is untrusted input. The initializer is trusted application configuration but may be loaded from source control, so it must not contain secret values.

TLS certificate and hostname verification remain enabled. Remote HTTP is rejected. Hostnames are canonicalized before comparison. All DNS answers are validated; mixed public/private results fail closed. The transport must not follow redirects to an unvalidated destination. Where the HTTP adapter exposes the connected peer address, it must match the validated address set; if it cannot prove that property for a hostname, the request fails closed rather than relying on a one-time DNS check.

The client must not log authorization headers, query strings containing credentials, full response bodies, or sensitive provider data. Logs may include provider name, sanitized host, operation category, elapsed time, and failure category. The global response-size and tool-output limits protect memory and MCP response size. Provider count, tool count, and total request budgets protect request duration.

The documented shutdown control is `config.context_providers.enabled = false`. The standalone CLI has an equivalent configuration option. Operators can also remove the allowlist without changing provider manifests.

## 9. Acceptance criteria

- `AC-1`: A configured provider remains completely inactive until the explicit enable switch and exact host allowlist are both present.
- `AC-2a`: A remote plain-HTTP endpoint is rejected before connection.
- `AC-2b`: Userinfo, fragments, hosts not in the allowlist, and unsafe ports are rejected before connection.
- `AC-2c`: IPv4 or IPv6 private, link-local, multicast, unspecified, and metadata destinations are rejected before connection.
- `AC-2d`: Mixed DNS answers are rejected before connection.
- `AC-2e`: A redirect to an unvalidated destination is rejected before the redirected request.
- `AC-3`: Only remote tools advertised as read-only and non-destructive can be called.
- `AC-4`: Provider results support simple and mapped tools, deterministic ordering, request memoization, response limits, and optional/required failure semantics.
- `AC-5`: `rails_get_provider_context` is separate from and does not alter local `rails_get_context`.
- `AC-6`: Normal Doctor runs make no network calls; explicit network mode reports pass, warning, or failure per provider.
- `AC-7`: No test or CI job reaches a public provider. Loopback integration tests prove the official MCP HTTP client path.
- `AC-8`: Provider configuration, security behavior, shutdown, downstream authentication, and migration steps are documented in the same release as the client.

## 10. Test approach

### Test seams

- `Registry::EndpointPolicy.new(resolver:, allowed_hosts:, allow_private_networks:)` accepts an injected DNS resolver and returns a resolved endpoint or a typed policy error. Tests never use the host machine's DNS.
- `Registry::ContextProviderClient.new(provider:, policy:, transport_factory:, auth_resolver:)` accepts an injected transport factory and auth resolver. Tests use fake MCP tool listings and responses.
- `Registry::ContextAggregator.new(manifest:, client_factory:, config:, scope:)` accepts an injected client factory and `ProviderRequestScope`. Tests do not open sockets.
- `Doctor.new(app, network: false)` passes the explicit value to `RegistryChecker#call(network:)`. Tests assert the client is untouched unless `network: true`.
- `Tools::GetProviderContext.call(provider: nil)` is tested through its MCP response, annotation metadata, limits, and error content.

- Prove `INV-1`, `INV-2`, `AC-1`, `AC-2a` through `AC-2e`, and `AC-3` with endpoint-policy and client tests using injected DNS and transport fakes.
- Prove `INV-3`, `INV-5`, `INV-6`, and `AC-7` with timeout, byte-cap, redirect, peer-address, and loopback integration tests. No public network is permitted.
- Prove `INV-4` with log and error assertions that fail if tokens, userinfo, query credentials, or response bodies appear.
- Prove `INV-7` and `AC-6` with Doctor calls that assert the client is not invoked unless the explicit network flag is set.
- Prove `INV-8` and `AC-5` with a local context tool spec that stubs any provider client and asserts it is never called.
- Prove `INV-9` and `AC-4` with simple, mapped, empty, optional-failure, required-failure, unknown-provider, count-cap, and deterministic-order examples.
- Prove `INV-10` with client exceptions and an `ensure`-observing fake transport.
- Run focused specs red before each implementation slice, then run the full RSpec suite, RuboCop, Reek, YARD, ArchSpec, mutation tests, and the supported Rails/Ruby matrix. The v5 release gate is at least 90% global line coverage and 90% global branch coverage; provider work must not reduce either metric.

## 11. Risks and tradeoffs

- DNS validation cannot by itself eliminate every rebinding race. The adapter must compare the connected peer where possible and fail closed where it cannot prove the connection target.
- Exact host allowlists require configuration when a provider host changes. This is intentional: the allowlist is committed configuration, so every trust-boundary change appears in the normal version-control diff.
- Sequential requests are slower when many providers are declared. This keeps v5 behavior easy to bound and cancel; parallel execution can be measured and added later.
- Remote read-only annotations are an assurance from the provider. Rejecting missing annotations protects this gem's contract but may exclude older servers.
- The SDK client reduces protocol code but brings Faraday and upstream lifecycle behavior into the compatibility matrix.

## 12. Open questions

No open question blocks implementation. OAuth token acquisition, provider health caching, retries, parallel calls, and non-MCP provider types are deferred to a later release.

## 13. Migration from v4

Existing v4 installations make no outbound provider requests. Upgrading to v5 does not enable requests, change `rails_get_context`, or require a manifest change. Hosts that want providers must add the provider declarations, explicitly enable `config.context_providers.enabled`, configure exact allowed hosts, and provide downstream auth through the resolver. The v5 upgrade guide must show how to disable the feature during rollout and how to remove the allowlist as an emergency shutdown.

## 14. Out of scope

- Arbitrary URL fetching or a user-controlled HTTP proxy.
- Remote tools without explicit non-destructive annotations.
- Secrets in `registry.json`, generated context, CLI config, or logs.
- Automatic Doctor network checks.
- Persistent or background provider sessions.
- Brakeman, test generation, PR review automation, and code-level dependency graphs.
