# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Markdown formatters for {Tools::GetModelDetails}.
    module ModelDetails
      # Renders model names with association and validation counts.
      class StandardFormatter
        # @param models [Hash{String => Hash}] model name => introspection payload
        # @return [void]
        def initialize(models:)
          @models = models
        end

        ##
        # Builds a Markdown summary of models including semantic tier and counts of associations and validations.
        #
        # The output lists models in alphabetical order, omitting any model whose payload contains `:error`.
        # Each model is rendered as a bullet with its name, optionally followed by `— tier: <value>` when
        # `:semantic_tier` is present, and optionally followed by `— X associations, Y validations` when
        # either count is greater than zero. A header with the total model count and a trailing instruction
        # line are included.
        # @return [String] The generated Markdown string listing models, tiers, and association/validation counts.
        def call
          lines = [ "# Models (#{@models.size})", "" ]

          @models.keys.sort.each do |name|
            data = @models[name]
            next if data[:error]

            assoc_count = (data[:associations] || []).size
            val_count   = (data[:validations] || []).size
            line = "- **#{name}**"
            line += " — tier: #{data[:semantic_tier]}" if data[:semantic_tier].present?
            line += " — #{assoc_count} associations, #{val_count} validations" if assoc_count > 0 || val_count > 0
            lines << line
          end

          lines << "" << "_Use `model:\"Name\"` for full detail, or `detail:\"full\"` for association lists._"
          lines.join("\n")
        end
      end
    end
  end
end
