# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Markdown formatters for {Tools::GetModelDetails}.
    module ModelDetails
      # Renders a bare list of model names with a total count.
      class SummaryFormatter
        # @param models [Hash{String => Hash}] model name => introspection payload
        ##
        # Construct a new SummaryFormatter with the given model introspection data.
        # @param [Hash<String, Hash>] models - Mapping of model name to its introspection payload; keys are model names and values are hashes (may contain :semantic_tier).
        def initialize(models:)
          @models = models
        end

        ##
        # Produce a Markdown summary listing available model names with optional semantic-tier annotations and a total count.
        # The list is sorted by model name; each entry is rendered as a bullet point and includes " (tier)" when a model's `:semantic_tier` is present.
        ##
        # Builds a Markdown summary of available models including the total count, an alphabetized bullet list with optional semantic-tier annotations, and a usage footer.
        # @return [String] The Markdown-formatted summary containing a header `# Available models (N)`, a newline-separated bullet list where each item is `- Name` optionally suffixed with ` (tier)`, and the footer `_Use `model:"Name"` for full detail._`
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
