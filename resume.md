# Internal Review Summary: `rails-ai-context` Fork

Reviewed repository: `igmarin/rails-ai-context`  
Review date: **2026-03-18**

## 1. What this gem does

`rails-ai-context` is a Rails engine/gem that introspects a host Rails application and exposes that structure to AI coding tools.

It does this in two ways:

1. It generates project files such as `CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, `.ai-context.json`, and in this fork also `AGENTS.md` for Codex.
2. It exposes a read-only MCP server with tools such as `rails_get_schema`, `rails_get_routes`, `rails_get_model_details`, and `rails_search_code`.

This fork keeps the original architecture, adds Codex-oriented output, and updates fork-specific metadata and operational documentation.

## 2. Is the gem safe?

### Short answer

**Reasonably yes, with operational caveats.**

The code reviewed does **not** show destructive MCP tools, shell injection through normal tool use, unsafe SQL patterns, or obvious secret leakage paths. The main risk is not arbitrary code execution by the gem itself. The main risk is **information exposure** if MCP outputs are made available to the wrong audience.

### Security positives

- All MCP tools are declared read-only.
- `rails_search_code` uses `Open3.capture2(*cmd)` with argument arrays, avoiding shell interpolation.
- Search paths are constrained under `Rails.root`, which reduces path traversal risk.
- Generated files are written only through known serializer paths.
- The gem does not make outbound network requests as part of normal operation.
- This fork now handles invalid regex input in the Ruby fallback path for `rails_search_code` with a controlled response instead of raising `RegexpError`.

### Real security risks

#### 1. HTTP MCP exposure

If the HTTP transport is enabled and reachable by an untrusted network, a caller may inspect:

- schema names
- route structure
- controller names
- model names and relationships
- code search results
- selected configuration metadata

This is not destructive, but it may still be sensitive.

#### 2. “Read-only” does not mean “low sensitivity”

The gem does not mutate application state, but it can still reveal internal engineering details. In regulated or high-sensitivity environments, generated assistant files and MCP responses should be treated as internal documentation.

#### 3. Supply chain risk still exists

The gem depends on:

- `mcp`
- `railties`
- `thor`
- `zeitwerk`

Known-vulnerability scanning is necessary over time even if the current code looks safe.

## 3. Can I use it safely?

### Recommended usage

- **Best fit:** local development with stdio MCP and trusted AI tooling.
- **Acceptable:** localhost-only HTTP transport in a controlled developer machine.
- **Not recommended without extra controls:** public or semi-public environments with `auto_mount` or network-exposed HTTP transport.

### Safe usage guidelines

- Prefer `rails ai:serve` over HTTP when possible.
- If HTTP is needed, keep binding on `127.0.0.1`.
- Do not expose the mounted MCP endpoint without explicit network and auth controls.
- Treat generated files such as `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, and `.ai-context.json` as internal project artifacts.
- Use `excluded_models` and `excluded_paths` when parts of the application should not be surfaced to AI tooling.

## 4. Code quality and architecture

### Review result

The codebase is in good shape for a Rails gem of this size.

- `RSpec`: green during review
- `RuboCop`: green during review
- clear split between introspection, MCP tools, serializers, and file generation

### Architecture summary

- `Introspector` orchestrates sub-introspectors and isolates failures per subsystem.
- `Tools::BaseTool` centralizes caching and response truncation.
- `ContextFileSerializer` fans the same introspection data into multiple assistant formats.
- The serializer architecture is a strong extension point, which made Codex support a good fit for the fork.

### Review observations

- Some instruction content is duplicated across serializers; this is acceptable now, but worth centralizing if more assistant formats are added.
- The introspector resolver remains explicit and easy to read, even if a registry-based approach could reduce repetition later.

## 5. Ruby and Rails compatibility

### Host app question resolved

Your host application uses **Rails 8.x** with **Ruby 3.3.10**.

That is compatible with the gem design, because the gem runs inside the same Ruby process as the host app. The gem does **not** run under a separate Ruby version at runtime.

### Practical conclusion

- Developing the fork on Ruby `3.4.9` is fine.
- The important part is that the gem continues to work when executed by the host app on Ruby `3.3.10`.
- The repository already declares `required_ruby_version >= 3.2.0` and has CI coverage for Ruby `3.2`, `3.3`, and `3.4` with Rails `7.1`, `7.2`, and `8.0`.

## 6. Codex support in this fork

This fork now adds initial Codex support through:

- `AGENTS.md` generation
- `.codex/README.md` helper output
- `rails ai:context:codex`

### Why this design makes sense

Current Codex documentation centers repository guidance around `AGENTS.md`. That makes a serializer-based project file the right integration point. It is more stable and more shareable than relying only on personal `~/.codex` files.

### Scope choice

This fork intentionally keeps `.codex/` support lightweight. It does **not** generate speculative project-local skills or unsupported Codex internals. The primary supported artifact is `AGENTS.md`.

## 7. Dependency and supply chain review

During the prior review pass:

- `bundle install` completed successfully
- `bundler-audit check --update` reported **No vulnerabilities found**
- the resolved `mcp` gem version was `0.8.0`
- the `mcp` gemspec showed a direct dependency on `json-schema`

### Recommendation

Keep `bundler-audit` in CI for the fork and re-run it whenever:

- `mcp` changes
- Rails dependency bounds change
- release preparation begins

## 8. Fork-specific documentation and governance

This fork should point users to the fork maintainer for:

- vulnerability reporting
- code of conduct reports
- bug reports and PRs

Keeping upstream contact details in a maintained fork creates confusion and delays. For that reason, the fork documentation was updated to use fork-owned contact points instead of mixing fork and upstream operational ownership.

## 9. Final recommendation

### Safe enough to use?

**Yes**, provided you use it with the right threat model:

- local or trusted environments
- stdio preferred
- localhost HTTP only unless additional controls exist
- awareness that read-only introspection can still expose sensitive engineering details

### Safe enough to fork and extend?

**Yes.**

The serializer-oriented design, existing CI matrix, and test coverage make this a practical project to fork for Codex support without needing a large rewrite.

### Highest-priority ongoing precautions

1. Keep HTTP MCP local unless explicitly protected.
2. Keep supply-chain scanning in CI.
3. Avoid overstating support beyond tested Ruby/Rails combinations.
4. Keep fork metadata, reporting contacts, and release metadata consistent with the fork.
