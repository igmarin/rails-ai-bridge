# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Providers
      # Generates the MCP Tool Reference section for compact serializers.
      #
      # This long-form guide (tables, detail limits) is embedded from {Providers::BaseProviderSerializer}.
      # It intentionally differs from {Providers::McpToolReferenceFormatter}, which serves rules-oriented
      # serializers with a shorter summary. Unify content only when product or documentation explicitly
      # requires both surfaces to match.
      class McpGuideFormatter < Base
        # @return [String] markdown block ready to embed in a compact context file
        def call
          <<~MARKDOWN.rstrip
            ## MCP Tool Reference

            This project exposes live MCP tools. **Always start with `detail:"summary"`**,
            then drill into specifics with a filter or `detail:"full"`.

            ### Detail levels (schema, routes, models, controllers)

            | Level | Returns | Default limit |
            |-------|---------|---------------|
            | `summary` | Names + counts | 50 |
            | `standard` | Names + key details | 15 (default) |
            | `full` | Everything (indexes, FKs, etc.) | 5 |

            ### rails_get_schema
            Params: `table`, `detail`, `limit`, `offset`, `format`
            - `rails_get_schema(detail:"summary")` — all tables with column counts
            - `rails_get_schema(table:"users")` — full detail for one table
            - `rails_get_schema(detail:"summary", limit:20, offset:40)` — paginate

            ### rails_get_model_details
            Params: `model`, `detail`
            - `rails_get_model_details(detail:"summary")` — list all model names
            - `rails_get_model_details(model:"User")` — associations, validations, scopes, enums, callbacks
            - `rails_get_model_details(detail:"full")` — all models with full association lists

            ### rails_get_routes
            Params: `controller`, `detail`, `limit`, `offset`
            - `rails_get_routes(detail:"summary")` — route counts per controller
            - `rails_get_routes(controller:"users")` — routes for one controller
            - `rails_get_routes(detail:"full", limit:50)` — full table with route names

            ### rails_get_controllers
            Params: `controller`, `detail`
            - `rails_get_controllers(detail:"summary")` — names + action counts
            - `rails_get_controllers(controller:"UsersController")` — actions, filters, strong params

            ### Other tools (no detail param)
            - `rails_get_config` — cache store, session, timezone, middleware, initializers
            - `rails_get_test_info` — test framework, factories/fixtures, CI config, coverage
            - `rails_get_gems` — notable gems categorized by function (auth, background jobs, etc.)
            - `rails_get_conventions` — architecture patterns, directory structure, config files
            - `rails_search_code(pattern:"regex", file_type:"rb", max_results:20)` — ripgrep search
          MARKDOWN
        end
      end
    end
  end
end
