# MCP Tool Reference

Detail levels: summary | standard (default) | full

## Schema
rails_get_schema(table:"name"|detail:"summary"|limit:N|offset:N)

## Models
rails_get_model_details(model:"Name"|detail:"summary")

## Routes
rails_get_routes(controller:"name"|detail:"summary"|limit:N|offset:N)

## Controllers
rails_get_controllers(controller:"Name"|detail:"summary")

## Other
- rails_get_config — cache, session, middleware
- rails_get_test_info — framework, factories, CI
- rails_get_gems — categorized gems
- rails_get_conventions — architecture patterns
- rails_search_code(pattern:"regex"|file_type:"rb"|max_results:N)

Start with detail:"summary", then drill into specifics.