# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Builds the compact models section used by split rules serializers.
        class RulesModelSectionBuilder
          # Format string for the model section heading.
          SECTION_HEADER_FORMAT = '## Models (%d total)'

          # Format string for one model summary row.
          MODEL_ENTRY_FORMAT = '- %s (%d associations)'

          # Format string for the overflow hint when not all models fit.
          MODELS_OVERFLOW_FORMAT = '- _...%d more — `rails_get_model_details(detail:"summary")`._'

          # Message shown when the configured model list limit is zero or negative.
          MODELS_LIMIT_ZERO_FORMAT = '- _Use `rails_get_model_details(detail:"summary")` for names._'

          # @param models [Hash, nil] models context keyed by model name
          # @param config [RailsAiBridge::Configuration] serializer configuration
          def initialize(models:, config:)
            @models = models
            @config = config
          end

          # @return [Array<String>] model-section lines or an empty array when models are unavailable
          def call
            return [] unless valid_models?

            lines = [format(SECTION_HEADER_FORMAT, @models.size)]
            model_list_limit.positive? ? add_model_entries(lines) : lines << MODELS_LIMIT_ZERO_FORMAT
            lines << ''
          end

          private

          def add_model_entries(lines)
            sorted_model_names.each { |model_name| lines << model_entry(model_name) }
            lines << format(MODELS_OVERFLOW_FORMAT, overflow_count) if overflow_count.positive?
          end

          def model_entry(model_name)
            ModelEntry.new(model_name, @models[model_name], MODEL_ENTRY_FORMAT).to_s
          end

          def sorted_model_names
            ContextSummary.models_by_relevance(@models).map(&:first).first(model_list_limit)
          rescue TypeError, ArgumentError
            []
          end

          def overflow_count
            [@models.size - model_list_limit, 0].max
          rescue TypeError, NoMethodError
            0
          end

          def valid_models?
            @models.is_a?(Hash) && !@models[:error] && @models.any?
          end

          def model_list_limit
            @config.copilot_compact_model_list_limit.to_i
          rescue TypeError, NoMethodError
            5
          end

          # Formats one compact model row.
          class ModelEntry
            # @param name [String] model name
            # @param data [Hash, nil] model payload
            # @param format_string [String] row format
            def initialize(name, data, format_string)
              @name = name
              @data = data
              @format_string = format_string
            end

            # @return [String] formatted model row
            def to_s
              format(@format_string, @name, association_count)
            end

            private

            def association_count
              associations.size
            end

            def associations
              return [] unless @data.is_a?(Hash)

              associations_payload = @data[:associations]
              associations_payload.is_a?(Array) ? associations_payload : []
            end
          end
        end
      end
    end
  end
end
