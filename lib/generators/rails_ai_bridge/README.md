# `lib/generators/rails_ai_bridge`

This folder contains install-time developer experience for host apps.

## Purpose

The install generator is responsible for creating the minimum working setup:

- `.mcp.json`
- `config/initializers/rails_ai_bridge.rb`
- `config/rails_ai_bridge/overrides.md`
- `config/rails_ai_bridge/overrides.md.example`

It also triggers initial bridge-file generation when Rails is fully loaded.

## Expectations

Generator behavior should stay:

- idempotent
- explicit about what changed
- aligned with current configuration defaults
- covered by generator specs

## Important file

- `install/install_generator.rb`: the main install flow and user-facing setup messages.

If the runtime contract changes, update the generator comments and setup output in the same change.
