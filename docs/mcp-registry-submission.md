# MCP Registry submission guide

This document contains the exact steps to list rails-ai-bridge in the
[official MCP Registry](https://github.com/modelcontextprotocol/registry).
The artifact (`server.json` at the repository root) is already
submission-ready and passes the official validator; only the final publish
step is left, and it requires the maintainer's GitHub account (the
`io.github.igmarin/` namespace can only be published by `igmarin` or a
GitHub Action running in igmarin's repos).

Status of `server.json` (verified at authoring time; re-run Step 2 before publishing):

- `mcp-publisher validate server.json` → ✅ valid against
  https://registry.modelcontextprotocol.io
- `version` `5.1.0` matches `RailsAiBridge::VERSION` (parity spec guards
  this; see #245)
- `name` `io.github.igmarin/rails-ai-bridge` matches the required
  reverse-DNS pattern and the GitHub namespace ownership rule
- `description` is exactly at the schema's 100-character maximum
- No `packages` entry on purpose: RubyGems is **not** one of the registry's
  supported package types (`npm`, `pypi`, `nuget`, `cargo`, `oci`, `mcpb`),
  so the listing is metadata-only. Clients install via `bundle add`, which
  the README documents.
- No `remotes` entry on purpose: the HTTP transport is host-app-specific
  (e.g. `http://127.0.0.1:3000/mcp`), not a hosted endpoint.

## Prerequisites

- You are signed in to GitHub as `igmarin` (namespace ownership).
- The version in `server.json` equals `RailsAiBridge::VERSION`
  (`ruby -r ./lib/rails_ai_bridge/version -e "puts RailsAiBridge::VERSION"`).
  Both are bumped together on release — the release workflow already fails a
  tag whose version does not match the gem.

## Step 1 — Install the publisher CLI

```bash
brew install mcp-publisher
# or, without sudo (extracts into the current directory):
curl -L "https://github.com/modelcontextprotocol/registry/releases/latest/download/mcp-publisher_$(uname -s | tr '[:upper:]' '[:lower:]')_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" | tar xz mcp-publisher && ./mcp-publisher --help
```

Verify:

```bash
mcp-publisher --help
```

## Step 2 — Validate the artifact (no account needed)

```bash
mcp-publisher validate server.json
```

Expected output:

```text
Validating against https://registry.modelcontextprotocol.io...
✅ server.json is valid
```

(Already confirmed at authoring time with `mcp-publisher` 1.8.1.)

## Step 3 — Re-check version sync, then commit any bump

If `RailsAiBridge::VERSION` moved since validation, update
`server.json`'s `version` (and `description`'s tool count only if the tool
count changed) in the same release commit, then re-run Step 2.

## Step 4 — Authenticate (maintainer-only)

```bash
mcp-publisher login github
```

Follow the device-code flow (visit https://github.com/login/device, enter
the printed code). The token authorizes publishing under
`io.github.igmarin/...` only.

## Step 5 — Publish

```bash
mcp-publisher publish
```

Expected output:

```text
Publishing to https://registry.modelcontextprotocol.io...
✓ Successfully published
✓ Server io.github.igmarin/rails-ai-bridge version <VERSION>
```

## Step 6 — Verify the listing

```bash
curl "https://registry.modelcontextprotocol.io/v0.1/servers?search=io.github.igmarin/rails-ai-bridge"
```

The response JSON should contain `"name":"io.github.igmarin/rails-ai-bridge"`
with the published version.

## Step 7 — Update these docs

1. Update the `README.md` badge (search for "MCP Registry") from the
   grey-blue `submission_ready` state to a green `listed` badge linking to
   `https://registry.modelcontextprotocol.io` search results.
2. Move the `[Unreleased]` CHANGELOG entry about the registry submission
   under the released version if it is still unreleased at publish time.

## Optional: automate on release

The registry supports GitHub OIDC publishing from Actions
(`mcp-publisher publish` inside a `permissions: id-token: write` job). A
follow-up could append a `registry` job to `.github/workflows/release.yml`
after the gem push step. That is intentionally out of scope here — do it
once the manual listing works.

## References

- Registry project: https://github.com/modelcontextprotocol/registry
- Publishing quickstart:
  https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/quickstart.mdx
- Supported package types (why RubyGems is not listed):
  https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/package-types.mdx
- `server.json` schema:
  https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json
