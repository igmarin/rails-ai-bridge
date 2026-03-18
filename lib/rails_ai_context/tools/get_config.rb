# frozen_string_literal: true

module RailsAiContext
  module Tools
    class GetConfig < BaseTool
      tool_name "rails_get_config"
      description "Get Rails application configuration including cache store, session store, timezone, middleware stack, and initializers."

      input_schema(properties: {})

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(server_context: nil)
        data = cached_context[:config]
        return text_response("Config introspection not available. Add :config to introspectors or use `config.preset = :full`.") unless data
        return text_response("Config introspection failed: #{data[:error]}") if data[:error]

        lines = [ "# Application Configuration", "" ]
        lines << "- **Cache store:** #{data[:cache_store]}" if data[:cache_store]
        lines << "- **Session store:** #{data[:session_store]}" if data[:session_store]
        lines << "- **Timezone:** #{data[:timezone]}" if data[:timezone]

        if data[:middleware_stack]&.any?
          lines << "" << "## Middleware Stack"
          data[:middleware_stack].each { |m| lines << "- #{m}" }
        end

        if data[:initializers]&.any?
          lines << "" << "## Initializers"
          data[:initializers].each { |i| lines << "- `#{i}`" }
        end

        if data[:current_attributes]&.any?
          lines << "" << "## CurrentAttributes"
          data[:current_attributes].each { |c| lines << "- `#{c}`" }
        end

        text_response(lines.join("\n"))
      end
    end
  end
end
