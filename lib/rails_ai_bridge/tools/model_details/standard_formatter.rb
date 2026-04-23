# frozen_string_literal: true

module RailsAiBridge
  module Tools
    module ModelDetails
      # Renders ActiveRecord model names with association and validation counts (and optional tier).
      class StandardFormatter
        # @param models [Hash{String => Hash}] payloads may include +:associations+, +:validations+, +:semantic_tier+, +:error+
        # @param non_ar_models [Hash, nil] optional +:non_ar_models+ section; appended via {NonArModelsAppendix}
        def initialize(models:, non_ar_models: nil)
          @models = models
          @non_ar_models = non_ar_models
        end

        # Builds Markdown with header `# Models (N)` and one line per non-errored model, plus optional POJO appendix.
        #
        # @return [String] Markdown document
        def call
          lines = ["# Models (#{@models.size})", '']

          @models.keys.sort.each do |name|
            data = @models[name]
            next if data[:error]

            assoc_count = (data[:associations] || []).size
            val_count   = (data[:validations] || []).size
            line = "- **#{name}**"
            line += " — tier: #{data[:semantic_tier]}" if data[:semantic_tier].present?
            if assoc_count.positive? || val_count.positive?
              line += " — #{assoc_count} associations, #{val_count} validations"
            end
            lines << line
          end

          lines << '' << '_Use `model:"Name"` for full detail, or `detail:"full"` for association lists._'
          lines.join("\n") + NonArModelsAppendix.append_markdown(@non_ar_models)
        end
      end
    end
  end
end
