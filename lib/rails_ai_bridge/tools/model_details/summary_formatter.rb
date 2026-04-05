# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Markdown formatters for {Tools::GetModelDetails}.
    module ModelDetails
      # Renders a bare list of model names with a total count.
      class SummaryFormatter
        # @param models [Hash{String => Hash}] model name => introspection payload
        # @return [void]
        def initialize(models:)
          @models = models
        end

        ##
        # Produce a Markdown summary listing available model names with optional semantic-tier annotations and a total count.
        # The list is sorted by model name; each entry is rendered as a bullet point and includes " (tier)" when a model's `:semantic_tier` is present.
        # @return [String] A Markdown-formatted summary containing a header `# Available models (N)`, a newline-separated bullet list of models (each optionally suffixed with ` (tier)`), and the footer `_Use `model:"Name"` for full detail._`
        def call
          model_list = @models.keys.sort.map do |m|
            data = @models[m]
            tier = data.is_a?(Hash) ? data[:semantic_tier] : nil
            suffix = tier.present? ? " (#{tier})" : ""
            "- #{m}#{suffix}"
          end.join("\n")
          "# Available models (#{@models.size})\n\n#{model_list}\n\n_Use `model:\"Name\"` for full detail._"
        end
      end
    end
  end
end
