# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool returning ActiveRecord model metadata or a listing with configurable detail.
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

      # @param model [String, nil] ActiveRecord class name for full detail; omit to list models
      # @param detail [String] +summary+, +standard+, or +full+ when listing
      # @param server_context [Object, nil] reserved for MCP transport metadata
      # @return [MCP::Tool::Response] markdown model output or an error message
      def self.call(model: nil, detail: "standard", server_context: nil)
        models = cached_section(:models)
        return text_response("Model introspection not available. Add :models to introspectors.") unless models
        return text_response("Model introspection failed: #{models[:error]}") if models[:error]

        formatter = ResponseFormatter.new(models, model: model, detail: detail)
        return text_response(formatter.model_not_found_message) if formatter.model_not_found?
        return text_response(formatter.model_error_message) if formatter.model_error?

        text_response(formatter.format)
      end

      # @private
      # Formats +:models+ introspection for {GetModelDetails}.
      class ResponseFormatter
        def initialize(models, model:, detail:)
          @models = models
          @model = model
          @detail = detail
        end

        def model_not_found?
          @model && !model_data
        end

        def model_not_found_message
          "Model '#{@model}' not found. Available: #{@models.keys.sort.join(', ')}"
        end

        def model_error?
          @model && model_data && model_data[:error]
        end

        def model_error_message
          "Error inspecting #{model_key}: #{model_data[:error]}"
        end

        def format
          if @model
            ModelDetails::SingleModelFormatter.new(name: model_key, data: model_data).call
          else
            formatter_class = case @detail
            when "summary" then ModelDetails::SummaryFormatter
            when "full"    then ModelDetails::FullFormatter
            else                ModelDetails::StandardFormatter
            end
            formatter_class.new(models: @models).call
          end
        end

        private

        def model_key
          @model_key ||= @models.keys.find { |k| k.downcase == @model.downcase } || @model
        end

        def model_data
          @model_data ||= @models[model_key]
        end
      end
    end
  end
end
