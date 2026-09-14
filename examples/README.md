# Examples

## demo_app — a minimal runnable Rails app

`demo_app/` is a tiny Rails 8 app (3 models, 3 controllers, 3 tables) that
exists to show rails-ai-bridge working end to end without a database. The gem
parses `db/schema.rb` as static text, so nothing here ever connects to a
database — the app boots, generates context files, and answers MCP tool calls
using the static schema.

### Why a full mini-app (decision + rationale)

Two shapes were considered:

1. **A tiny bootable Rails app under `examples/`** (this choice)
2. **A prose walkthrough reusing the `spec/fixtures/apps` scaffolds**

The fixture apps are skeletons (`app/`, `config/routes.rb`, `db/schema.rb`
only) that cannot boot, so option 2 could only show *described* behavior, not
runnable behavior. A new user can reproduce everything here in under five
minutes with three commands, and every output snippet in
[docs/EXAMPLES.md](../docs/EXAMPLES.md) was captured by actually running this
app against the gem in this repository.

### Run it

From the repository root:

```bash
cd examples/demo_app
bundle install
bundle exec bin/rails generate rails_ai_bridge:install --profile=minimal
bundle exec bin/rails ai:bridge
```

Then open `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.devinrules`,
`.github/copilot-instructions.md`, `GEMINI.md`, and `.mcp.json` — all were
generated from this 3-model app. The committed versions of those files are
the real generator output, so you can read them without running anything.

### Try the MCP tools

```bash
bundle exec bin/rails ai:serve   # stdio MCP server; ask any MCP client
```

Example tool calls with real output are in
[docs/EXAMPLES.md](../docs/EXAMPLES.md).

### In your own app

You do not copy `demo_app/` anywhere — you add the gem to your own project:

```bash
bundle add rails-ai-bridge
rails generate rails_ai_bridge:install
rails ai:bridge
```

The demo app exists to show what you get before you run it on your codebase.

### Versions used for the captured output

The output snippets in [docs/EXAMPLES.md](../docs/EXAMPLES.md) were captured
with the repository checkout at the time of writing (Ruby 4.0.6, Rails
8.1.3.1, gem version 5.1.0). The gem itself requires Ruby >= 3.2 and
Rails >= 7.1; your generated files will embed your own versions.
