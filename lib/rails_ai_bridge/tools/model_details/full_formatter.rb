# frozen_string_literal: true

module RailsAiBridge
  module Tools
    module ModelDetails
      # Renders ActiveRecord model names with table names, tiers, and full association lists.
      class FullFormatter
        # @param models [Hash{String => Hash}] payloads may include +:table_name+, +:semantic_tier+, +:associations+, +:error+
        # @param non_ar_models [Hash, nil] optional +:non_ar_models+ section; appended via {NonArModelsAppendix}
        def initialize(models:, non_ar_models: nil)
          @models = models
          @non_ar_models = non_ar_models
        end

        # Builds Markdown with header `# Models (N)` and detailed bullets per model, plus optional POJO appendix.
        #
        # @return [String] Markdown document
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
          lines.join("\n") + NonArModelsAppendix.append_markdown(@non_ar_models)
        end
      end
    end
  end
end
