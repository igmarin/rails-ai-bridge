# frozen_string_literal: true

# rails-ai-bridge configuration
# All settings are commented out — uncomment only what you need to change.
# Defaults are production-safe: read-only introspection, no HTTP exposure.
# Run `rails ai:doctor` after changes to verify your setup.

RailsAiBridge.configure do |config|
  # ---------------------------------------------------------------------------
  # Introspector preset
  # ---------------------------------------------------------------------------
  # Controls how much of your app is introspected when generating context files
  # and answering MCP tool requests.
  #
  # :standard (default) — 9 core introspectors covering the essentials:
  #   schema, models, routes, controllers, jobs, gems, conventions, tests, migrations
  #   Best for most apps. Fast and focused.
  #
  # :full — all 27 introspectors (everything in :standard plus):
  #   views, Turbo/Stimulus, auth, API serializers, config, assets, DevOps
  #   Use for full-stack Hotwire apps or when AI needs frontend/auth/API context.
  #
  # :regulated — 6 introspectors — omits schema, models, and migrations.
  #   Use for apps with strict data governance where schema must not be exposed.
  #
  # config.preset = :standard   # already the default — uncomment only to switch

  # Add individual introspectors on top of the preset (does not change the preset):
  # Effect: each listed symbol enables one additional introspector.
  # config.introspectors += %i[non_ar_models views turbo auth api database_stats]
  #
  # database_stats: adds small/medium/large/hot hints to table context using
  # PostgreSQL table statistics. Opt-in because it queries the DB at introspection time.

  # Disable a whole category at runtime (overrides preset and individual additions):
  # :domain_metadata disables schema + models + migrations + non_ar_models
  # config.disabled_introspection_categories << :domain_metadata

  # ---------------------------------------------------------------------------
  # Security exclusions
  # ---------------------------------------------------------------------------
  # These settings control what gets included in generated context files and
  # MCP tool responses. Excluded items are silently omitted — not replaced.

  # Tables to hide from schema introspection and model output.
  # Accepts exact table names or globs ("pii_*" matches pii_users, pii_logs, etc.)
  # Effect: excluded tables disappear from rails_get_schema and model details.
  # config.excluded_tables += %w[secrets audit_logs pii_*]

  # ActiveRecord models to exclude from introspection.
  # Effect: excluded models are not listed in any generated context file or MCP response.
  # config.excluded_models += %w[AdminUser InternalAuditLog]

  # Paths excluded from rails_search_code results.
  # Effect: files under these paths are skipped in code search results.
  # config.excluded_paths += %w[vendor/bundle node_modules]

  # ---------------------------------------------------------------------------
  # Domain model hints
  # ---------------------------------------------------------------------------
  # Mark your primary business models as core_entity. This affects:
  #   - Ordering in generated context files (core models listed first)
  #   - Semantic tier in rails_get_model_details responses ("core_entity")
  #   - .claude/rules/rails-models.md (tagged for Claude Code)
  # Effect: these models get promoted in AI context. Use your 3-7 most central models.
  # config.core_models += %w[User Order Project]

  # ---------------------------------------------------------------------------
  # Context output
  # ---------------------------------------------------------------------------
  # Controls how much detail goes into generated static files (CLAUDE.md, AGENTS.md, etc.)
  #
  # :compact (default) — ≤150 lines per file. Key models and routes are listed;
  #   everything else is referenced via MCP tools. Suitable for large apps.
  #   The AI asks MCP for details on demand — no context bloat.
  #
  # :full — dumps everything into the static files. No MCP needed for orientation,
  #   but files can be large. Best for small apps with fewer than ~30 models.
  #
  # config.context_mode = :compact   # already the default

  # Max lines for CLAUDE.md in compact mode (default: 150):
  # config.claude_max_lines = 150

  # Safety cap for MCP tool responses in characters (default: 120_000):
  # Oversized responses are truncated with a hint to use filters or pagination.
  # config.max_tool_response_chars = 120_000

  # Team-specific rules merged into Copilot and Codex output.
  # Effect: content of overrides.md is appended to .github/copilot-instructions.md
  # and AGENTS.md on each `rails ai:bridge` run.
  # IMPORTANT: Remove the first-line "<!-- rails-ai-bridge:omit-merge -->" guard
  # from config/rails_ai_bridge/overrides.md before this has any effect.
  # config.assistant_overrides_path = "config/rails_ai_bridge/overrides.md"

  # Keep hand-authored prose inline in CLAUDE.md / AGENTS.md / GEMINI.md.
  # When true, generated content is confined to a marked block:
  #   <!-- BEGIN rails-ai-bridge: generated ... -->  ...  <!-- END rails-ai-bridge -->
  # Anything you write above or below that block survives every regeneration, and an
  # existing file without markers gets the block appended rather than overwritten.
  # Never applies to .ai-context.json. Per-run override: `MERGE=1 rails ai:bridge`.
  # config.output.managed_region = true

  # Shared verify-before-write rules in compact CLAUDE.md / AGENTS.md / GEMINI.md /
  # Copilot / Cursor output. Default is on; set false to omit the block.
  # config.output.anti_hallucination_rules = false

  # Model list size caps for compact output (0 = show no names, only MCP pointer):
  # Reduce these for apps with large model counts to keep files within size limits.
  # config.copilot_compact_model_list_limit = 15   # default
  # config.codex_compact_model_list_limit   = 15   # default

  # ==========================================================================
  # HTTP MCP / auto_mount — SECURITY CRITICAL
  # ==========================================================================
  # By default, MCP runs only via stdio (`rails ai:serve`), which is local-only
  # and safe. The HTTP transport is an opt-in alternative for clients that cannot
  # spawn sub-processes (e.g. browser-based AI tools, remote agents).
  #
  # Even though tools are read-only, the HTTP endpoint exposes routes, schema,
  # and code structure. Treat it as an internal service — keep it on localhost
  # unless you add authentication AND network controls.
  #
  # To enable HTTP MCP locally (development only):
  #   config.auto_mount = true
  #   config.http_path  = "/mcp"        # endpoint path
  #   config.http_bind  = "127.0.0.1"   # localhost only
  # Then start your Rails server and point your AI client to http://localhost:3000/mcp
  #
  # For production, you MUST also set allow_auto_mount_in_production = true AND
  # configure one of these auth mechanisms (highest priority first):
  #
  #   1. JWT decoder (bring your own JWT gem):
  #      config.mcp_jwt_decoder = ->(token) {
  #        JWT.decode(token, credentials.jwt_secret, true, algorithm: "HS256").first
  #      rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::ImmatureSignature
  #        nil
  #      }
  #
  #   2. Token resolver (Devise, database lookup, etc.):
  #      config.mcp_token_resolver = ->(token) { User.find_by(mcp_api_token: token) }
  #
  #   3. Static shared secret (simplest — fine for internal tools):
  #      config.http_mcp_token = "generate-a-long-random-secret"
  #      # ENV["RAILS_AI_BRIDGE_MCP_TOKEN"] takes precedence when set
  #
  # Require authentication on every HTTP MCP request. When true, requests
  # return 401 unless one of the auth mechanisms above is configured.
  # Default is false for backward compatibility with local development.
  # config.mcp.require_http_auth = true
  # See docs/mcp-security.md — Residual risk checklist (operators).
  #
  # Timing-safe token comparison is built in, but add rate limiting too
  # (e.g. Rack::Attack throttle on config.http_path) to prevent brute-force.
  #
  # CORS for browser-based AI clients connecting over SSE.
  # Default is nil (no CORS headers). Set to ['*'] to allow any origin,
  # or to a list of exact origins such as ['https://app.example.com'].
  # config.mcp.cors_origins = ['https://app.example.com']
  #
  # config.auto_mount = false
  # config.allow_auto_mount_in_production = false
  # config.http_path = "/mcp"
  # config.http_port = 6029

  # ---------------------------------------------------------------------------
  # Outbound context providers (v5)
  # ---------------------------------------------------------------------------
  # rails_get_provider_context fetches context from declared external MCP
  # services. Disabled by default — no DNS or network calls unless enabled.
  # See docs/v5/context-providers-design.md and docs/mcp-security.md.
  #
  # config.context_providers.enabled = true
  # config.context_providers.allowed_hosts = ['context.example.com']
  # config.context_providers.allowed_loopback_ports = [3000, 9292]
  # config.context_providers.timeout_seconds = 10
  # config.context_providers.aggregation_budget_seconds = 30
  # config.context_providers.max_response_bytes = 1_048_576
  # config.context_providers.max_providers = 8
  # config.context_providers.max_tools_per_provider = 16
  #
  # Auth resolver — returns headers for a trusted provider identity.
  # Called with (endpoint, canonical_uri) at request time.
  # Never put tokens in the registry manifest.
  # config.context_providers.auth_resolver = lambda do |endpoint, canonical_uri|
  #   { 'Authorization' => "Bearer #{token_for(canonical_uri.host)}" }
  # end
  #
  # WARNING: Enabling allow_private_networks permits connections to internal
  # network addresses; use it only for controlled development endpoints.
  # config.context_providers.allow_private_networks = false
end
