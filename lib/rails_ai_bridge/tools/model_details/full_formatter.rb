# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Markdown formatters for {Tools::GetModelDetails}.
    module ModelDetails
      # Renders model names with their full association lists and table names.
      class FullFormatter
        # @param models [Hash{String => Hash}] model name => introspection payload
        ##
        # Create a FullFormatter configured with model introspection data.
        # @param [Hash<String, Hash>] models - A mapping of model name to its introspection payload (each payload may include keys such as :table_name, :semantic_tier, :associations, and :error). The hash is stored for use when rendering the formatter output.
        def initialize(models:)
          @models = models
        end

        ##
        # Builds a Markdown listing of models including table name, semantic tier, and associations.
        #
        # Models that contain an `:error` key are omitted from the output.
        # Each model is rendered on its own line; a final footer provides a usage hint.
        ##
        # Generates a Markdown document summarizing the stored models.
        #
        # The output begins with a header "# Models (N)" where N is the number of models,
        # followed by one bullet line per model (models with `data[:error]` are omitted).
        # Each model line includes the model name and, when present, the table name,
        # the semantic tier, and a comma-separated list of associations. The document
        # ends with an instruction line for querying model details.
        #
        # @return [String] The Markdown document containing the header, one line per included model, and the footer instruction.
        def call
          lines = [ "# Models (#{@models.size})", "" ]

          @models.keys.sort.each do |name|
            data = @models[name]
            next if data[:error]

            assocs = (data[:associations] || []).map { |a| "#{a[:type]} :#{a[:name]}" }.join(", ")
            line = "- **#{name}**"
            line += " (table: #{data[:table_name]})" if data[:table_name]
            line += " — tier: #{data[:semantic_tier]}" if data[:semantic_tier].present?
            line += " — #{assocs}" unless assocs.empty?
            lines << line
          end

          lines << "" << "_Use `model:\"Name\"` for validations, scopes, callbacks, and more._"
          lines.join("\n")
        end
      end
    end
  end
end
