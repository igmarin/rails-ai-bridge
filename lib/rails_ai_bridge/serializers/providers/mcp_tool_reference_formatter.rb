# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Formats the static MCP Tool Reference section.
      # This content is typically hardcoded as it describes the generic MCP tool interface
      # rather than app-specific introspection results.
      class McpToolReferenceFormatter < RailsAiBridge::Serializers::Providers::Base
        # Renders the MCP Tool Reference section as a Markdown string.
        #
        # @return [String] The formatted MCP tool reference markdown.
        def call
          %Q{
## MCP Tool Reference

All introspection tools support detail:"summary"|"standard"|"full".
Start with summary, drill into specifics with a filter.

### rails_get_schema
Params: table, detail, limit, offset, format
- `rails_get_schema(detail:"summary")` — all tables with column counts
- `rails_get_schema(table:"users")` — full detail for one table
- `rails_get_schema(detail:"summary", limit:20, offset:40)` — paginate

### rails_get_model_details
Params: model, detail
- `rails_get_model_details(detail:"summary")` — list model names
- `rails_get_model_details(model:"User")` — full associations, validations, scopes

### rails_get_routes
Params: controller, detail, limit, offset
- `rails_get_routes(detail:"summary")` — route counts per controller
- `rails_get_routes(controller:"users")` — routes for one controller

### rails_get_controllers
Params: controller, detail
- `rails_get_controllers(detail:"summary")` — names + action counts
- `rails_get_controllers(controller:"UsersController")` — full detail

### Other tools
- `rails_get_config` — cache, session, middleware, timezone
- `rails_get_test_info` — framework, factories, CI
- `rails_get_gems` — categorized gem analysis
- `rails_get_conventions` — architecture patterns
- `rails_search_code(pattern:"regex", file_type:"rb", max_results:20)` — codebase search
}
        end
      end
    end
  end
end
