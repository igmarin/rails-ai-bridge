# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Assembles the full compact project rules document.
        class RulesDocumentBuilder
          # Format string for the project rules document heading.
          PROJECT_RULES_HEADER = '# %s — Project Rules'

          # Format string for Rails and Ruby version metadata.
          VERSION_INFO_FORMAT = 'Rails %s | Ruby %s'

          # @param context [Hash] introspection context
          # @param config [RailsAiBridge::Configuration] serializer configuration
          def initialize(context:, config:)
            @context = context
            @config = config
          end

          # @return [Array<String>] rules document lines
          def call
            [
              header_lines,
              SharedAssistantGuidance.compact_engineering_rules_lines,
              main_section_lines,
              ['', *SharedAssistantGuidance.repo_specific_guidance_section_lines],
              model_section_lines,
              mcp_tool_reference_lines,
              SharedAssistantGuidance.compact_engineering_rules_footer_lines(@context)
            ].flatten
          end

          private

          def header_lines
            [
              format(PROJECT_RULES_HEADER, @context[:app_name]),
              '',
              format(VERSION_INFO_FORMAT, @context[:rails_version], @context[:ruby_version]),
              ''
            ]
          end

          def main_section_lines
            [
              RulesStackOverviewBuilder.new(@context).call,
              RulesNotableGemsBuilder.new(@context[:gems]).call,
              RulesArchitectureBuilder.new(@context[:conventions]).call,
              RulesKeyConsiderationsBuilder.new(@context).call
            ]
          end

          def model_section_lines
            ['', *RulesModelSectionBuilder.new(models: @context[:models], config: @config).call]
          end

          def mcp_tool_reference_lines
            McpToolReferenceFormatter.new(context: @context).call.lines.map(&:chomp)
          end
        end
      end
    end
  end
end
