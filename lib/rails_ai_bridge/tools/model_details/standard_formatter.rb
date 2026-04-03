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

        # @return [String] Markdown listing with counts
        def call
          lines = [ "# Models (#{@models.size})", "" ]

          @models.keys.sort.each do |name|
            data = @models[name]
            next if data[:error]

            assoc_count = (data[:associations] || []).size
            val_count   = (data[:validations] || []).size
            line = "- **#{name}**"
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
