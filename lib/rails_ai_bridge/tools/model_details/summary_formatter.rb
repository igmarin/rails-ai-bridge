# frozen_string_literal: true

module RailsAiBridge
  module Tools
    module ModelDetails
      # Renders a bare list of model names with a total count.
      class SummaryFormatter
        # @param models [Hash] models hash keyed by class name
        def initialize(models:)
          @models = models
        end

        # @return [String] Markdown name listing
        def call
          model_list = @models.keys.sort.map { |m| "- #{m}" }.join("\n")
          "# Available models (#{@models.size})\n\n#{model_list}\n\n_Use `model:\"Name\"` for full detail._"
        end
      end
    end
  end
end
