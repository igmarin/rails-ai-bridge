# `lib/rails_ai_bridge/tools`

This folder contains the MCP tool classes exposed to AI clients.

## Contract

Each tool should:

- inherit from `RailsAiBridge::Tools::BaseTool`
- define `tool_name`, `description`, and `input_schema`
- expose a class-level `.call`
- return `MCP::Tool::Response`
- stay read-only

## Shared helpers

Use `BaseTool` helpers instead of rolling your own runtime behavior:

- `cached_context` for a full snapshot
- `cached_section(:name)` for section-level reads
- `text_response(text)` for truncation-safe responses

## When to use `cached_section`

Prefer `cached_section` when the tool only needs one introspection section:

- `:schema`
- `:routes`
- `:models`
- `:controllers`
- `:config`
- `:tests`

Use `cached_context` only when the tool genuinely needs multiple sections at once.

## Registration

Built-in tools are listed in `lib/rails_ai_bridge/server.rb`.

Custom tools can be appended with:

```ruby
RailsAiBridge.configure do |config|
  config.additional_tools << MyCompany::Tools::GetBillingContext
end
```
