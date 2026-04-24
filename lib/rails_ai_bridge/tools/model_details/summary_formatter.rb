# frozen_string_literal: true

module RailsAiBridge
  module Tools
    module ModelDetails
      # Renders a bare list of ActiveRecord model names with optional semantic-tier annotations.
      class SummaryFormatter
        # @param models [Hash{String => Hash}] model name => introspection payload (may include +:semantic_tier+)
        # @param non_ar_models [Hash, nil] optional +:non_ar_models+ section; appended via {NonArModelsAppendix}
        def initialize(models:, non_ar_models: nil)
          @models = models
          @non_ar_models = non_ar_models
        end

        # Builds Markdown with header `# Available models (N)`, sorted ActiveRecord bullets, footer, and optional POJO appendix.
        #
        # @return [String] Markdown document
        def call
          model_list = @models.keys.sort.map do |m|
            data = @models[m]
            tier = data.is_a?(Hash) ? data[:semantic_tier] : nil
            suffix = tier.present? ? " (#{tier})" : ''
            "- #{m}#{suffix}"
          end.join("\n")
          base = "# Available models (#{@models.size})\n\n#{model_list}\n\n_Use `model:\"Name\"` for full detail._"
          base + NonArModelsAppendix.append_markdown(@non_ar_models)
        end
      end
    end
  end
end
