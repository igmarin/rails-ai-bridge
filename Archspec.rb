# frozen_string_literal: true

# ArchSpec architecture specification for rails-ai-bridge.
#
# Defines ten components and the dependency directions the gem is expected to
# follow. Lower layers (core, config, introspectors, registry, rubydex,
# serializers) must not reach up into transport or tooling layers.
# Cross-component cycles are forbidden.
#
# Run locally with:
#
#   bundle exec archspec check
#
# See https://archspecrb.dev for the full DSL guide.

source 'lib/rails_ai_bridge/**/*.rb'

# Core primitives — dependency-free value types and pure helpers (Service,
# Service::Result, ExclusionHelper, DatabaseSize) that every layer may use.
# Extracted per the #250 diagnosis "durable alternative".
component :core, in: %w[
  lib/rails_ai_bridge/service.rb
  lib/rails_ai_bridge/service/**/*.rb
  lib/rails_ai_bridge/exclusion_helper.rb
  lib/rails_ai_bridge/database_size.rb
  lib/rails_ai_bridge/service_errors.rb
]

# Configuration layer — user-facing settings and presets.
# Must stay free of upper-layer dependencies so it can be loaded in isolation.
component :config, in: %w[
  lib/rails_ai_bridge/configuration.rb
  lib/rails_ai_bridge/config/**/*.rb
]

# Introspection layer — reads the host Rails app and returns plain Hashes.
# Must not depend on MCP tools, output formatters, or the transport layer.
component :introspectors, in: %w[
  lib/rails_ai_bridge/introspector.rb
  lib/rails_ai_bridge/introspector/**/*.rb
  lib/rails_ai_bridge/introspectors/**/*.rb
]

# Runtime context — supporting infrastructure shared by tools and serializers
# (context providers, fingerprinting, watcher, tasks, errors).
component :runtime_context, in: %w[
  lib/rails_ai_bridge/assistant_formats_preference.rb
  lib/rails_ai_bridge/cache_warmer.rb
  lib/rails_ai_bridge/context_provider.rb
  lib/rails_ai_bridge/fingerprinter.rb
  lib/rails_ai_bridge/fingerprinter/**/*.rb
  lib/rails_ai_bridge/freshness_header.rb
  lib/rails_ai_bridge/instrumentation.rb
  lib/rails_ai_bridge/tasks/**/*.rb
  lib/rails_ai_bridge/tool_result_cache.rb
  lib/rails_ai_bridge/view_file_analyzer.rb
  lib/rails_ai_bridge/watcher.rb
  lib/rails_ai_bridge/watcher/**/*.rb
]

# Host integration — Rails engine wiring, diagnostics, MCP resources that
# AI clients read directly, plus service orchestrators that sit above the
# formatting and transport layers. Entry-point glue: it may use every other
# component (engine wires middleware, doctor checkers reach downward, service
# orchestrators call serializers); nothing may depend on it. The gem entry
# point (lib/rails_ai_bridge.rb) sits outside all components.
component :host_integration, in: %w[
  lib/rails_ai_bridge/engine.rb
  lib/rails_ai_bridge/doctor.rb
  lib/rails_ai_bridge/doctor/**/*.rb
  lib/rails_ai_bridge/services/**/*.rb
]

# MCP tools — the 20 built-in tools exposed over the MCP protocol.
component :tools, in: 'lib/rails_ai_bridge/tools/**/*.rb'

# Output formatters — serialize introspection payloads to per-assistant files.
# Must not invoke introspection or transport directly.
component :serializers, in: 'lib/rails_ai_bridge/serializers/**/*.rb'

# Skill pack registry — resolves and loads external skill packs.
# Must not depend on tools, serializers, or the transport layer.
component :registry, in: %w[
  lib/rails_ai_bridge/registry.rb
  lib/rails_ai_bridge/registry/**/*.rb
]

# MCP transport — the server, Rack middleware, HTTP app, auth/rate-limiting, and
# the MCP resources registry (resources are part of the MCP protocol surface;
# Server wires Resources at construction).
component :mcp_transport, in: %w[
  lib/rails_ai_bridge/server.rb
  lib/rails_ai_bridge/middleware.rb
  lib/rails_ai_bridge/http_transport_app.rb
  lib/rails_ai_bridge/mcp/**/*.rb
  lib/rails_ai_bridge/resources.rb
]

# Rubydex integration — optional semantic code analysis adapter.
# Must not depend on tools, serializers, or the transport layer.
component :rubydex, in: %w[
  lib/rails_ai_bridge/rubydex_adapter.rb
  lib/rails_ai_bridge/rubydex_adapter/**/*.rb
]

# --- Dependency direction rules ---

# Core is the bottom of the stack; every layer may use it, it uses nothing.
core.cannot_use :config, :introspectors, :runtime_context, :tools, :serializers,
                :registry, :mcp_transport, :rubydex, :host_integration

# Config sits directly above core; it must not reach up into any upper layer.
config.cannot_use :runtime_context, :tools, :serializers, :mcp_transport, :introspectors,
                  :host_integration

# Runtime context, tools, and transport sit below host integration wiring;
# they must not reach up into it.
runtime_context.cannot_use :host_integration
tools.cannot_use :host_integration
mcp_transport.cannot_use :host_integration

# Registry and rubydex are leaf adapters; they must not depend on the
# tooling, formatting, or transport layers.
registry.cannot_use :tools, :serializers, :mcp_transport, :host_integration
rubydex.cannot_use :tools, :serializers, :mcp_transport, :host_integration

# Introspectors produce plain data and must not depend on tools, formatters,
# or transport.
introspectors.cannot_use :tools, :serializers, :mcp_transport, :host_integration

# Serializers format data handed to them; they must not invoke introspection
# or reach into the transport layer.
serializers.cannot_use :introspectors, :mcp_transport, :host_integration

# Cross-component cycles are forbidden across all defined components.
no_cycles among: %i[core config introspectors runtime_context tools serializers
                    registry mcp_transport rubydex host_integration]
