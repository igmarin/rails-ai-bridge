# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetModelDetails < BaseTool
      tool_name "rails_get_model_details"
      description "Get detailed information about a specific ActiveRecord model including associations, validations, scopes, enums, callbacks, and concerns. If no model specified, lists all available models with configurable detail level."

      input_schema(
        properties: {
          model: {
            type: "string",
            description: "Model class name (e.g. 'User', 'Post'). Omit to list all models."
          },
          detail: {
            type: "string",
            enum: %w[summary standard full],
            description: "Detail level for model listing. summary: names only. standard: names + association/validation counts (default). full: names + full association list. Ignored when specific model is given (always returns full)."
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(model: nil, detail: "standard", server_context: nil)
        models = cached_section(:models)
        return text_response("Model introspection not available. Add :models to introspectors.") unless models
        return text_response("Model introspection failed: #{models[:error]}") if models[:error]

        if model
          key  = models.keys.find { |k| k.downcase == model.downcase } || model
          data = models[key]
          return text_response("Model '#{model}' not found. Available: #{models.keys.sort.join(', ')}") unless data
          return text_response("Error inspecting #{key}: #{data[:error]}") if data[:error]
          return text_response(ModelDetails::SingleModelFormatter.new(name: key, data: data).call)
        end

        formatter_class = case detail
        when "summary" then ModelDetails::SummaryFormatter
        when "full"    then ModelDetails::FullFormatter
        else                ModelDetails::StandardFormatter
        end

        text_response(formatter_class.new(models: models).call)
      end
    end
  end
end
