# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Builds architecture and convention lines for compact rules output.
        class RulesArchitectureBuilder
          # Heading used for the architecture section.
          SECTION_HEADER = '## Architecture & Conventions'

          # Format string for a single architecture entry.
          ARCHITECTURE_ENTRY_FORMAT = '- %s'

          # @param conventions [Hash, nil] conventions context payload
          def initialize(conventions)
            @conventions = conventions
          end

          # @return [Array<String>] architecture lines, or empty when unavailable
          def call
            return [] unless architecture.any?

            [SECTION_HEADER, *architecture_lines]
          end

          private

          def architecture_lines
            architecture.map { |entry| format(ARCHITECTURE_ENTRY_FORMAT, entry.humanize) }
          end

          def architecture
            @conventions.is_a?(Hash) ? Array(@conventions[:architecture]) : []
          end
        end
      end
    end
  end
end
