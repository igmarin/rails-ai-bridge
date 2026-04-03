# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetConfig < BaseTool
      tool_name "rails_get_config"
      description "Get Rails application configuration including cache store, session store, timezone, middleware stack, and initializers."

      input_schema(properties: {})

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(server_context: nil)
        data = cached_section(:config)
        return text_response("Config introspection not available. Add :config to introspectors or use `config.preset = :full`.") unless data
        return text_response("Config introspection failed: #{data[:error]}") if data[:error]

        formatter = ResponseFormatter.new(data)
        text_response(formatter.format)
      end

      # @private
      class ResponseFormatter
        def initialize(config_data)
          @config_data = config_data
        end

        def format
          lines = [ "# Application Configuration", "" ]
          lines << "- **Cache store:** #{@config_data[:cache_store]}" if @config_data[:cache_store]
          lines << "- **Session store:** #{@config_data[:session_store]}" if @config_data[:session_store]
          lines << "- **Timezone:** #{@config_data[:timezone]}" if @config_data[:timezone]

          if @config_data[:middleware_stack]&.any?
            lines << "" << "## Middleware Stack"
            @config_data[:middleware_stack].each { |m| lines << "- #{m}" }
          end

          if @config_data[:initializers]&.any?
            lines << "" << "## Initializers"
            @config_data[:initializers].each { |i| lines << "- `#{i}`" }
          end

          if @config_data[:current_attributes]&.any?
            lines << "" << "## CurrentAttributes"
            @config_data[:current_attributes].each { |c| lines << "- `#{c}`" }
          end

          lines.join("\n")
        end
      end
    end
  end
end
