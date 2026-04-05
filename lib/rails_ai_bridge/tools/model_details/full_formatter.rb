# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Markdown formatters for {Tools::GetModelDetails}.
    module ModelDetails
      # Renders model names with their full association lists and table names.
      class FullFormatter
        # @param models [Hash{String => Hash}] model name => introspection payload
        # @return [void]
        def initialize(models:)
          @models = models
        end

        ##
        # Builds a Markdown listing of models including table name, semantic tier, and associations.
        #
        # Models that contain an `:error` key are omitted from the output.
        # Each model is rendered on its own line; a final footer provides a usage hint.
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
