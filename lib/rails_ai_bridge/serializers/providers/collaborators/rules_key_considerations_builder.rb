# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Builds the key development considerations section for compact rules output.
        class RulesKeyConsiderationsBuilder
          # Heading used for the key development considerations section.
          SECTION_HEADER = '## Key Development Considerations'

          # Format strings for supported consideration rows.
          FORMAT_STRINGS = {
            test_framework: '- **Test Framework:** `%s`',
            cache_store: '- **Cache Store:** `%s`'
          }.freeze

          # @param context [Hash] introspection context
          def initialize(context)
            @context = context
          end

          # @return [Array<String>] considerations section lines, or empty when unavailable
          def call
            return [] unless considerations?

            ConsiderationLines.new(context: @context, formats: FORMAT_STRINGS).to_a
          end

          private

          def considerations?
            (@context[:tests] || @context[:config]) && valid_considerations_data?
          end

          def valid_considerations_data?
            @context[:tests].is_a?(Hash) || @context[:config].is_a?(Hash)
          end

          # Formats populated consideration rows.
          class ConsiderationLines
            # @param context [Hash] introspection context
            # @param formats [Hash] row format strings
            def initialize(context:, formats:)
              @context = context
              @formats = formats
            end

            # @return [Array<String>] formatted section lines
            def to_a
              lines = [SECTION_HEADER]
              lines << test_framework_line if test_framework_present?
              lines << cache_store_line if cache_store_present?
              lines
            end

            private

            def test_framework_line
              format(@formats[:test_framework], tests[:framework])
            end

            def cache_store_line
              format(@formats[:cache_store], config[:cache_store])
            end

            def test_framework_present?
              tests[:framework].present?
            end

            def cache_store_present?
              config[:cache_store].present?
            end

            def tests
              section(:tests)
            end

            def config
              section(:config)
            end

            def section(name)
              payload = @context[name]
              payload.is_a?(Hash) ? payload : {}
            end
          end
        end
      end
    end
  end
end
