# `lib/rails_ai_bridge`

This folder contains the runtime core of `rails-ai-bridge`.

## Purpose

These files define the public API, configuration surface, MCP runtime wiring, and the internal boundaries used to introspect a Rails app and expose that data to AI clients.

## Key files

- `configuration.rb`: global configuration object and extension registries.
- `context_provider.rb`: shared runtime cache for full context snapshots and per-section fetches.
- `introspector.rb`: orchestrates built-in and custom introspectors.
- `server.rb`: builds the MCP server and registers tools/resources.
- `resources.rb`: serves `rails://...` resources through the shared context provider.
- `middleware.rb`: Rack middleware for auto-mounted HTTP MCP.
- `http_transport_app.rb`: shared Rack endpoint used by both `Server` and `Middleware`.
- `fingerprinter.rb`: file-change detection used for cache invalidation.
- `doctor.rb`: diagnostics and readiness checks.
- `watcher.rb`: file watcher that regenerates bridge files in development.

## Runtime flow

1. `RailsAiBridge.introspect` delegates to `Introspector`.
2. `ContextProvider` caches either the full snapshot or individual sections.
3. MCP tools and MCP resources read through `ContextProvider`.
4. `Server` or `Middleware` expose the data over stdio or HTTP.

## Extension points

The supported extension seams live on `RailsAiBridge.configuration`:

- `additional_introspectors`
- `additional_tools`
- `additional_resources`

Use these instead of patching internal constants.
