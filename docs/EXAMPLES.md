# Example: rails-ai-bridge on a real (tiny) app

This walkthrough was produced by running rails-ai-bridge v5.1.0 against
[`examples/demo_app`](../examples/demo_app) — a minimal Rails 8 app with 3
models (`User`, `Post`, `Comment`), 3 controllers, and 3 tables. Every output
below is real captured output, not a mockup. The app never connects to a
database: the gem parses `db/schema.rb` as static text and tags schema data
`[INFERRED]`.

Time to reproduce: under 5 minutes (Ruby 3.2+ and the repo cloned).

---

## 1. Install

From the repository root:

```bash
cd examples/demo_app
bundle install
```

In your own app you would instead use:

```bash
bundle add rails-ai-bridge
```

## 2. Run the install generator

```bash
bundle exec bin/rails generate rails_ai_bridge:install --profile=minimal
```

Captured output (abridged):

```text
==================================================
 rails-ai-bridge installed!
==================================================

Bridge commands:
  rails ai:bridge                              # Generate all bridge files (compact mode)
  ...

MCP: .mcp.json auto-detected by Claude Code and Cursor — no manual config needed.

Profile: minimal — Thin Cursor/Devin/Claude/Copilot/Gemini shims, no split rule directories.

Custom rules: edit config/rails_ai_bridge/overrides.md (remove omit-merge line to enable)

Commit bridge files and .mcp.json so your team benefits!
```

The generator creates `.mcp.json` and the initializer:

```json
{
  "mcpServers": {
    "rails-ai-bridge": {
      "command": "bundle",
      "args": ["exec", "rails", "ai:serve"]
    }
  }
}
```

## 3. Generate the context files

```bash
bundle exec bin/rails ai:bridge
```

Captured output (abridged):

```text
🔍 Introspecting DemoApp...
📝 Writing bridge files...
  ✅ .../demo_app/CLAUDE.md
  ✅ .../demo_app/AGENTS.md
  ✅ .../demo_app/.cursorrules
  ✅ .../demo_app/.devinrules
  ✅ .../demo_app/.github/copilot-instructions.md
  ✅ .../demo_app/GEMINI.md
  ✅ .../demo_app/.claude/rules/rails-context.md
  ✅ .../demo_app/.claude/rules/rails-schema.md
  ✅ .../demo_app/.claude/rules/rails-models.md
  ⏭️  .../demo_app/.codex/README.md (unchanged)
  ...

Done! Your AI assistants now understand your Rails app.
```

One run writes context for all 7 assistant targets. The committed files in
`examples/demo_app/` are this run's real output:

| Assistant target | File(s) | Size |
|---|---|---|
| Claude Code | `CLAUDE.md` + `.claude/rules/*.md` | 111 lines (compact) |
| OpenAI Codex | `AGENTS.md` + `.codex/README.md` | 98 lines |
| Cursor | `.cursorrules` + `.cursor/rules/*.mdc` | 108 lines |
| Devin | `.devinrules` + `.devin/rules/*.md` | 53 lines (≤5,800 chars) |
| GitHub Copilot | `.github/copilot-instructions.md` + `.github/instructions/*.md` | 136 lines |
| Gemini | `GEMINI.md` | 111 lines |
| JSON (generic) | `.ai-context.json` (regenerable cache, not committed) | — |

Sample of the generated `CLAUDE.md` (real output):

```markdown
## Stack
- Database: static_parse — 3 tables
- Models: 3
- Routes: 16 total — 2 controller classes (4 names in routing — can exceed class count when routes reference engines or non-file controllers)
- Endpoint focus: posts: 9 routes — `rails_get_routes(controller:"posts", detail:"summary")`; ...

## Key Models
The following are the most architecturally significant models, ordered by relevance:
- **Post** (2a, 3v) [cols: title:string, body:text, published:boolean] — belongs_to :user, has_many :comments
- **Comment** (1a, 2v) [cols: body:text, post:references] — belongs_to :post
- **User** (1a, 2v) [cols: email:string, name:string] — has_many :posts
```

Note the endpoint-focus hint: the assistant is told to call
`rails_get_routes(controller:"posts", detail:"summary")` instead of reading
all 16 routes. That is the compact-mode trade: small files, precise drills.

## 4. Call MCP tools

Start the server:

```bash
bundle exec bin/rails ai:serve
```

Claude Code and Cursor auto-detect `.mcp.json` and start this server
themselves. Below, each call was made against the stdio MCP server via
JSON-RPC (`tools/call`) — the same path an AI client uses.

### `rails_get_schema` (detail: summary)

```text
# Schema Summary (3 tables)

- **comments** [INFERRED] — 4 columns, 0 indexes
- **posts** [INFERRED] — 6 columns, 0 indexes
- **users** [INFERRED] — 4 columns, 0 indexes
```

`[INFERRED]` means the data came from a static parse of `db/schema.rb`
(no database connection). With a live database the same tool tags output
`[VERIFIED]`.

Note that the static parser counts only bare `add_index` statements in this
mode — inline `t.index` declarations inside a table block (as used in this
schema) are not reported, which is why every table shows `0 indexes`. The
counted columns and tables are accurate; index counts currently include only
bare `add_index` statements.

### `rails_get_routes` (detail: standard)

```text
# Routes (16 total)

## comments
- `POST` `/comments` → create (`comments_path`)
- `DELETE` `/comments/:id` → destroy (`comment_path`, id)

## posts
- `GET` `/` → index (`root_path`)
- `GET` `/posts` → index (`posts_path`)
- `POST` `/posts` → create
- `GET` `/posts/new` → new (`new_post_path`)
- `GET` `/posts/:id/edit` → edit (`edit_post_path`, id)
- `GET` `/posts/:id` → show (`post_path`, id)
- `PATCH` `/posts/:id` → update
- `PUT` `/posts/:id` → update
- `DELETE` `/posts/:id` → destroy
```

(Plus 4 `rails/info` diagnostic routes and `rails/welcome` defaults that
Rails itself registers in this bare app.)

### `rails_get_context` (model: Post)

One call that composes table + model + routes + controller for a single
feature — the "working on X" tool:

```text
# Context: Post

## Table

- **posts** [INFERRED] — 6 columns, 0 indexes

## Model

- **Post** — 2 associations, 3 validations, tier: `supporting`
- `belongs_to` **user** [VERIFIED]
- `has_many` **comments** [VERIFIED]
- `presence` on user
- `presence` on title
- `presence` on body

## Routes

- **posts** — 9 routes (`/`, `/posts`, `/posts`)

## Controller

- **PostsController** — create, index, show; filters: verify_authenticity_token, verify_same_origin_request
```

Association, validation, and callback facts come from the loaded model classes
(reflection), which is why they are tagged `[VERIFIED]` even though the app
never opens a database connection — the tag marks how the fact was sourced,
and model-source reflection is verified, unlike the static schema text parse.

## 5. Check readiness

```bash
bundle exec bin/rails ai:doctor
```

Captured output (abridged):

```text
  ✅ Schema: db/schema.rb found
  ✅ Models: 4 model files found
  ✅ Routes: config/routes.rb found
  ✅ Bridge files: CLAUDE.md exists
  ✅ Bridge file freshness: All generated bridge files are fresh
  ✅ MCP server: MCP server builds successfully
  ⚠️  Views: No view files found in app/views/
  ⚠️  Tests: No test directory found
  ...

AI Readiness Score: 85/100
```

---

## What this demonstrates

1. **Zero config** — install, generate, and the app is mapped.
2. **Works without a database** — schema introspection falls back to a static
   `db/schema.rb` parse and says so via the `[INFERRED]` tag.
3. **Compact by default** — a 111-line `CLAUDE.md` for the whole app, with
   MCP tools for on-demand detail.
4. **`[VERIFIED]` vs `[INFERRED]`** — the assistant knows which facts came
   from a live connection versus static parsing.

## Where to go next

- [README](../README.md) — full feature list and client wiring
- [docs/GUIDE.md](GUIDE.md) — every command, config option, and tool parameter
- [docs/BEST_PRACTICES.md](BEST_PRACTICES.md) — day-to-day usage patterns
