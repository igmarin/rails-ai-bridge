# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Builds stack metadata lines for compact rules output.
        class RulesStackOverviewBuilder
          SECTION_HEADER = '## Application Stack & Overview'
          FORMAT_STRINGS = {
            app_name: '- **Name:** `%s`',
            rails_version: '- **Rails:** `%s`',
            ruby_version: '- **Ruby:** `%s`',
            environment: '- **Environment:** `%s`',
            database_adapter: '- **Database:** `%s`'
          }.freeze

          # @param context [Hash] introspection context
          def initialize(context)
            @context = context
          end

          # @return [Array<String>] stack overview lines, or empty when no metadata exists
          def call
            return [] unless stack_metadata?

            [SECTION_HEADER, *metadata_lines]
          end

          private

          def stack_metadata?
            FORMAT_STRINGS.keys.any? { |key| @context[key].present? }
          end

          def metadata_lines
            FORMAT_STRINGS.filter_map do |key, format_string|
              value = @context[key]
              format(format_string, value) if value
            end
          end
        end
      end
    end
  end
end
