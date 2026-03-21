# Contributing to rails-ai-bridge

Thanks for your interest in contributing! This guide covers everything you need to get started.

## Development Setup

```bash
git clone https://github.com/igmarin/rails-ai-bridge.git
cd rails-ai-bridge
bundle install
bundle exec rspec
bundle exec rubocop --parallel
```

The test suite uses [Combustion](https://github.com/pat/combustion) to boot a minimal Rails app in `spec/internal/`. No external database required — tests run against an in-memory SQLite database.

## Project Structure

```
lib/rails_ai_bridge/
├── introspectors/     # 27 introspectors (schema, models, routes, etc.)
├── tools/             # 9 MCP tools with detail levels and pagination
├── serializers/       # Per-assistant formatters (claude, cursor, windsurf, copilot, JSON)
├── server.rb          # MCP server setup (stdio + HTTP)
├── engine.rb          # Rails Engine for auto-integration
└── configuration.rb   # User-facing config (presets, context_mode, limits)
```

## Adding a New Introspector

1. Create `lib/rails_ai_bridge/introspectors/your_introspector.rb` (auto-loaded by Zeitwerk)
2. Implement `#initialize(app)` and `#call` → returns a Hash (never raises)
3. Register it in `lib/rails_ai_bridge/introspector.rb` (the `INTROSPECTOR_MAP`)
4. Add the key to the appropriate preset(s) in `Configuration::PRESETS` (`:standard` for core, `:full` for all)
5. Write specs in `spec/lib/rails_ai_bridge/your_introspector_spec.rb`

## Adding a New MCP Tool

1. Create `lib/rails_ai_bridge/tools/your_tool.rb` inheriting from `BaseTool` (auto-loaded by Zeitwerk)
2. Define `tool_name`, `description`, `input_schema`, and `annotations`
3. Implement `def self.call(...)` returning `text_response(string)`
4. Register in `Server::TOOLS`
5. Write specs in `spec/lib/rails_ai_bridge/tools/your_tool_spec.rb`

## Code Style

- Follow `rubocop-rails-omakase` style (run `bundle exec rubocop`)
- Ruby 3.2+ features welcome (pattern matching, etc.)
- Every introspector must return a Hash and never raise — wrap errors in `{ error: msg }`
- MCP tools return `MCP::Tool::Response` objects
- All tools must be prefixed with `rails_` and annotated as read-only

## Running Tests

```bash
bundle exec rspec              # Full test suite
bundle exec rspec spec/lib/    # Just lib specs
bundle exec rubocop --parallel # Lint check
```

## Pull Request Process

1. Fork the repo and create your branch from `main`
2. Add tests for any new functionality
3. Ensure `bundle exec rspec` and `bundle exec rubocop` pass
4. Update CHANGELOG.md under an `## [Unreleased]` section
5. Open a PR with a clear title and description

## Reporting Bugs

Open an issue at https://github.com/igmarin/rails-ai-bridge/issues with:
- Ruby and Rails versions
- Gem version
- Steps to reproduce
- Expected vs actual behavior

## Releasing to RubyGems (maintainers)

Pre-flight checklist:

1. **Name availability** — Confirm `rails-ai-bridge` is available (or owned by you) on [RubyGems](https://rubygems.org/gems/rails-ai-bridge).
2. **Version** — `lib/rails_ai_bridge/version.rb` must match the Git tag (release workflow expects `v#{VERSION}`).
3. **Changelog** — Add a `## [x.y.z]` section in `CHANGELOG.md` (release notes are extracted from it in CI).
4. **Build locally** — `gem build rails-ai-bridge.gemspec` and smoke-test in a dummy Rails app (`rails generate rails_ai_bridge:install`, `rails ai:context`, `rails ai:serve`).
5. **MFA** — RubyGems account must have MFA; `spec.metadata["rubygems_mfa_required"]` is already `"true"`.
6. **Trusted publishing** — Prefer [OIDC trusted publishing](https://guides.rubygems.org/trusted-publishing/) with the existing `rubygems/release-gem@v1` workflow; configure the gem owner on RubyGems to trust this repository/workflow.
7. **Secrets** — Avoid API keys in the repo; rely on trusted publishing or short-lived CI secrets.
8. **MCP registry** — If you publish `server.json` to the MCP registry, coordinate the `name` field (`io.github.igmarin/rails-ai-bridge`) with registry requirements.
9. **Post-release** — Verify `bundle add rails-ai-bridge` from RubyGems and that badges in the README resolve.
