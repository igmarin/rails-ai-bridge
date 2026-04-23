# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool returning ActiveRecord model metadata, optional non-AR +app/models+ listings,
    # and configurable list detail for all models.
    class GetModelDetails < BaseTool
      tool_name 'rails_get_model_details'
      description 'Get detailed information about a specific ActiveRecord model including associations, validations, scopes, enums,
      callbacks, and concerns. If no model specified, lists all available models with configurable detail level. Non-ActiveRecord classes under app/models (POJO/Service) appear
    in listings when :non_ar_models introspection is enabled.'

      input_schema(
        properties: {
          model: {
            type: 'string',
            description: "Model class name (e.g. 'User', 'Post'). Omit to list all models."
          },
          detail: {
            type: 'string',
            enum: %w[summary standard full],
            description: 'Detail level for model listing. summary: names only. standard: names + association/validation counts (default). full: names + full association list.
            Ignored when specific model is given (always returns full).'
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # Returns Markdown for one model or for a full listing.
      #
      # Reads +:models+ and, when present, +:non_ar_models+ from {BaseTool.cached_section}.
      # When +model+ matches a non-AR entry and not an ActiveRecord key, returns a short POJO summary.
      #
      # @param model [String, nil] ActiveRecord class name for full detail via {ModelDetails::SingleModelFormatter};
      #   omit to list all ActiveRecord models with +detail+.
      # @param detail [String] +summary+, +standard+, or +full+ when listing (ignored when +model+ is set)
      # @param server_context [Object, nil] reserved for MCP transport metadata
      # @return [MCP::Tool::Response] Markdown body or an error string wrapped for the MCP client
      def self.call(model: nil, detail: 'standard', server_context: nil)
        models = cached_section(:models)
        return text_response('Model introspection not available. Add :models to introspectors.') unless models
        return text_response("Model introspection failed: #{models[:error]}") if models[:error]

        non_ar = cached_section(:non_ar_models)
        formatter = ResponseFormatter.new(models, model: model, detail: detail, non_ar_models: non_ar)
        return text_response(formatter.model_not_found_message) if formatter.model_not_found?
        return text_response(formatter.model_error_message) if formatter.model_error?

        text_response(formatter.format)
      end

      # @private
      # Orchestrates Markdown output for {.call}.
      class ResponseFormatter
        # @param models [Hash{String => Hash}] ActiveRecord introspection payload keyed by class name
        # @param model [String, nil] requested single-model name
        # @param detail [String] list detail level when +model+ is +nil+
        # @param non_ar_models [Hash, nil] +:non_ar_models+ introspection section (may be +nil+ if disabled)
        def initialize(models, model:, detail:, non_ar_models: nil)
          @models = models
          @model = model
          @detail = detail
          @non_ar_models = non_ar_models
        end

        # @return [Boolean] +true+ when a specific +model+ was requested but is neither AR nor a known POJO row
        def model_not_found?
          @model && !model_data && !pojo_entry
        end

        # @return [String] user-facing message listing available ActiveRecord and non-AR +app/models+ class names (sorted, deduplicated)
        def model_not_found_message
          pojo_names = ModelDetails::NonArModelsAppendix.entries_from(@non_ar_models).filter_map do |e|
            n = e[:name] || e['name']
            n.to_s.presence
          end
          available = (@models.keys.map(&:to_s) + pojo_names).uniq.sort
          "Model '#{@model}' not found. Available: #{available.join(', ')}"
        end

        # @return [Boolean] +true+ when the matched ActiveRecord payload contains +:error+
        def model_error?
          @model && model_data && model_data[:error]
        end

        # @return [String] user-facing error for a failed per-model introspection
        def model_error_message
          "Error inspecting #{model_key}: #{model_data[:error]}"
        end

        # @return [String] Markdown for one model, POJO stub, or full listing
        def format
          if @model
            return pojo_detail_markdown if pojo_entry && !model_data

            ModelDetails::SingleModelFormatter.new(name: model_key, data: model_data).call
          else
            formatter_class = case @detail
                              when 'summary' then ModelDetails::SummaryFormatter
                              when 'full'    then ModelDetails::FullFormatter
                              else ModelDetails::StandardFormatter
                              end
            formatter_class.new(models: @models, non_ar_models: @non_ar_models).call
          end
        end

        private

        def pojo_entry
          return @pojo_entry if defined?(@pojo_entry)

          @pojo_entry = ModelDetails::NonArModelsAppendix.entries_from(@non_ar_models).find do |e|
            name = e[:name] || e['name']
            name.to_s.casecmp?(@model.to_s)
          end
        end

        def pojo_detail_markdown
          e = pojo_entry
          name = e[:name] || e['name']
          path = e[:relative_path] || e['relative_path']
          tag = e[:tag] || e['tag'] || ModelDetails::NonArModelsAppendix::DEFAULT_TAG
          <<~MD.strip
            # #{name} (#{tag})

            Non-ActiveRecord class under `app/models` (not in ActiveRecord introspection).

            - **Source:** `#{path}`
            - **Note:** Use `rails_search_code` or open the file for implementation detail.
          MD
        end

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
