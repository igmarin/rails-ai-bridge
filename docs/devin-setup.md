# Devin CLI Setup Guide — rails-ai-bridge

This guide walks through setting up rails-ai-bridge for use with Devin CLI. By the end, Devin will have static context about your Rails application loaded at session start, and live MCP tools available for on-demand drill-down.

## Overview

rails-ai-bridge gives Devin two complementary layers:

- **Passive layer** — static files that Devin reads automatically at the start of every session, requiring no tool calls.
- **Active layer** — a live MCP server that Devin queries on demand for detailed, up-to-date information about your application.

Both layers are independent. You can start with just the static files and add MCP later.

---

## What Devin Reads Automatically

Devin CLI reads the following files from your project root without any configuration:

| File | Purpose |
|------|---------|
| `.devinrules` | Primary context file. Hard-capped at 5,800 characters (Devin enforces a 6K limit). Contains the most critical project overview. |
| `.devin/rules/*.md` | Supplementary rule files. Devin reads all Markdown files in this directory. |
| `AGENTS.md` | Codex-style instruction file. Devin reads this alongside `.devinrules`. |

The rails-ai-bridge generator produces:

- `.devinrules` — main context, truncated to stay within the 5,800-character cap
- `.devin/rules/rails-context.md` — project overview content that overflows from `.devinrules`
- `.devin/rules/rails-mcp-tools.md` — MCP tool reference so Devin knows what tools are available
- `AGENTS.md` — full project context and conventions in codex format

These files are regenerated from live application introspection each time you run the generator. They stay current with your schema, routes, and gems.

---

## Generating the Static Files

Run the Devin-specific generator:

```bash
bundle exec rails ai:bridge:devin
```

This writes `.devinrules`, `.devin/rules/rails-context.md`, `.devin/rules/rails-mcp-tools.md`, and `AGENTS.md`. Unchanged files are skipped (SHA256 fingerprinting prevents unnecessary writes).

To generate context files for all supported AI tools at once:

```bash
bundle exec rails ai:bridge
```

This runs all serializers, including Devin, Claude Code, Cursor, GitHub Copilot, and others. Use this when you want to keep all assistants in sync.

Regenerate these files whenever your schema, routes, or gem dependencies change significantly. A good time is after migrations or before starting a new feature.

---

## Wiring the MCP Server

The MCP server gives Devin live access to your application structure. It runs as a subprocess that Devin manages over stdio.

### Create `.devin/mcp.json`

The install generator creates `.mcp.json` at the project root for Claude Code and Cursor auto-discovery, but Devin uses a separate file at `.devin/mcp.json`. You must create this manually.

Create `.devin/mcp.json` in your project:

```json
{
  "mcpServers": {
    "rails-ai-bridge": {
      "command": "bundle",
      "args": ["exec", "rails", "ai:serve"],
      "cwd": "/absolute/path/to/your/rails/app"
    }
  }
}
```

Replace `/absolute/path/to/your/rails/app` with the absolute path to your Rails application root. Relative paths will not work — Devin requires an absolute `cwd`.

Commit this file to your repository so all team members using Devin get the same configuration.

### Available MCP Tools

Once connected, Devin has access to these tools:

| Tool | Description |
|------|-------------|
| `rails_get_schema` | Database schema — tables, columns, types, indexes |
| `rails_get_routes` | All named routes with HTTP methods and controllers |
| `rails_get_model_details` | Associations, validations, scopes for a specific model |
| `rails_get_gems` | Gemfile dependencies and their versions |
| `rails_search_code` | Full-text search across the codebase |
| `rails_search_semantic` | Semantic code search by concept |
| `rails_get_conventions` | Project coding conventions and patterns |
| `rails_get_controllers` | Controller actions and before-actions |
| `rails_get_config` | Application configuration values |
| `rails_get_test_info` | Test suite structure and coverage summary |
| `rails_get_view` | View templates and partials |
| `rails_get_stimulus` | Stimulus controllers and their targets/actions |
| `rails_list_registry` | List available AI skills from the skill registry |
| `rails_resolve_skill` | Retrieve a specific skill from the registry |

---

## Verifying the Connection

After adding `.devin/mcp.json`, start a Devin session in your project. Devin should report the MCP server as connected and list the available tools.

To confirm, ask Devin directly:

```
What MCP tools do you have available?
```

Devin should list tools including `rails_get_schema`, `rails_get_routes`, and the others above. If it does not, see the Troubleshooting section below.

You can also verify the server starts correctly by running it manually:

```bash
bundle exec rails ai:serve
```

If this command exits immediately with an error, the problem is in your Rails environment rather than the Devin configuration. Fix the Rails issue first, then revisit the MCP setup.

---

## Recommended Workflow

Use the two layers for different purposes:

**Static files for orientation** — at the start of a session, Devin reads `.devinrules` and `AGENTS.md` to understand the project structure, conventions, and domain. This costs no tool calls and happens automatically.

**MCP tools for drill-down** — when Devin needs specific information (the associations on a particular model, the routes for a namespace, test coverage for a controller), it calls the appropriate MCP tool. This returns current data directly from your running application.

A typical session looks like:

1. Devin loads `.devinrules` and `AGENTS.md` — understands the project at a high level.
2. Devin calls `rails_get_schema` to inspect the tables relevant to the task.
3. Devin calls `rails_get_model_details` with `detail: full` for the specific model it is working on.
4. Devin calls `rails_get_routes` to understand the routing structure.
5. Devin proceeds with implementation, calling `rails_search_code` as needed to find existing patterns.

This combination keeps the static context small (within Devin's limits) while giving full access to application detail when needed.

---

## Troubleshooting

### MCP server not connecting

Check that `.devin/mcp.json` exists at the project root (not inside a subdirectory) and that the JSON is valid. The `cwd` value must be an absolute path.

Verify by running:

```bash
cat .devin/mcp.json
```

### Tools not listed after connecting

The server may have started but exited before Devin could query it. Run `bundle exec rails ai:serve` manually and look for errors. Common causes are missing gems or a failed Rails boot.

### Ruby version manager issues (rbenv, rvm)

If Devin cannot find `bundle` or loads the wrong Ruby version, the shell environment inside the subprocess may not have your version manager initialized. Two options:

**Option 1 — Use an absolute path to bundle:**

Find the full path with `which bundle` or `rbenv which bundle`, then use it in `mcp.json`:

```json
{
  "mcpServers": {
    "rails-ai-bridge": {
      "command": "/Users/yourname/.rbenv/shims/bundle",
      "args": ["exec", "rails", "ai:serve"],
      "cwd": "/absolute/path/to/your/rails/app"
    }
  }
}
```

**Option 2 — Use HTTP transport instead of stdio** (see below).

### Wrong working directory

If the server starts but returns empty results, confirm that `cwd` in `.devin/mcp.json` points to the Rails root (the directory containing `Gemfile` and `config/application.rb`).

---

## HTTP Transport (Alternative to stdio)

If stdio is problematic — typically due to version manager PATH issues or process management constraints — use the HTTP transport instead.

Start the HTTP server as a background process in your Rails app:

```bash
bundle exec rails ai:serve_http
```

This starts a server at `http://127.0.0.1:6029/mcp` using SSE transport.

Configure `.devin/mcp.json` to connect over HTTP:

```json
{
  "mcpServers": {
    "rails-ai-bridge": {
      "type": "sse",
      "url": "http://127.0.0.1:6029/mcp"
    }
  }
}
```

With HTTP transport, you are responsible for keeping the server running. Add it to your development process (Procfile, tmux session, launchd, etc.) so it is available when Devin needs it.

---

## Skills Integration

rails-ai-bridge supports a skill registry — a collection of reusable AI skills that Devin can discover and apply to specific tasks.

The `rails_list_registry` tool returns all available skills. The `rails_resolve_skill` tool retrieves the full content of a named skill so Devin can apply it.

Skills are configured via `config/rails_ai_bridge_registry.json` in your Rails application. A minimal registry file looks like:

```json
{
  "skills": [
    {
      "name": "implement-service-object",
      "path": "docs/skills/implement-service-object.md",
      "description": "Pattern for creating service objects with .call interface"
    }
  ]
}
```

Each skill entry has a `name` (used as the identifier in `rails_resolve_skill`), a `path` relative to the Rails root, and a `description` that appears in `rails_list_registry` output.

Once configured, Devin can ask:

```
What skills are available in this project?
```

Devin will call `rails_list_registry`, review the options, and call `rails_resolve_skill` with the relevant skill name before proceeding with the task. This lets you encode project-specific patterns — service object conventions, API versioning rules, authorization approaches — and have Devin apply them consistently without repeating them in every session.

---

## File Reference

| File | Generator | Checked in? |
|------|-----------|-------------|
| `.devinrules` | `rails ai:bridge:devin` | Yes |
| `.devin/rules/rails-context.md` | `rails ai:bridge:devin` | Yes |
| `.devin/rules/rails-mcp-tools.md` | `rails ai:bridge:devin` | Yes |
| `AGENTS.md` | `rails ai:bridge:devin` | Yes |
| `.devin/mcp.json` | Manual | Yes |
| `config/rails_ai_bridge_registry.json` | Manual | Yes |
