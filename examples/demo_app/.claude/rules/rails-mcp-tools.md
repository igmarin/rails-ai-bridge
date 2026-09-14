# MCP Tool Reference

All introspection tools support a `detail` parameter:
- `summary` — names + counts (default limit: 50)
- `standard` — names + key details (default limit: 15, this is the default)
- `full` — everything including indexes, FKs (default limit: 5)

## rails_get_schema
Params: `table`, `detail`, `limit`, `offset`, `format`
- `rails_get_schema(detail:"summary")` — all tables with column counts
- `rails_get_schema(table:"users")` — full detail for one table
- `rails_get_schema(detail:"summary", limit:20, offset:40)` — paginate

## rails_get_model_details
Params: `model`, `detail`
- `rails_get_model_details(detail:"summary")` — list all model names
- `rails_get_model_details(model:"User")` — associations, validations, scopes, enums, callbacks
- `rails_get_model_details(detail:"full")` — all models with full association lists
- Plain Ruby classes under app/models (not ActiveRecord) appear in listings as [POJO/Service]; `model:"Name"` returns a short file-path summary.

## rails_get_routes
Params: `controller`, `detail`, `limit`, `offset`
- `rails_get_routes(detail:"summary")` — route counts per controller
- `rails_get_routes(controller:"users")` — routes for one controller
- `rails_get_routes(detail:"full", limit:50)` — full table with route names

## rails_get_controllers
Params: `controller`, `detail`
- `rails_get_controllers(detail:"summary")` — names + action counts
- `rails_get_controllers(controller:"UsersController")` — actions, filters, strong params

## Other tools (no detail param)
- `rails_get_config` — cache store, session, timezone, middleware, initializers
- `rails_get_test_info` — test framework, factories/fixtures, CI config, coverage
- `rails_get_gems` — notable gems categorized by function
- `rails_get_conventions` — architecture patterns, directory structure
- `rails_search_code(pattern:"regex", file_type:"rb", max_results:20)` — codebase search

## Workflow
1. Start with `detail:"summary"` to understand the landscape
2. Drill into specifics with filters (`table:`, `model:`, `controller:`)
3. Use `detail:"full"` only when you need indexes, FKs, constraints
4. Paginate large results with `limit` and `offset`