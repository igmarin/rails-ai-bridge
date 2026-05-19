# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates compact, imperative-tone rules for legacy `.cursorrules`.
      # In +:compact+ mode (default), output points editors at MCP tools and repo conventions.
      # In +:full+ mode, delegates to {MarkdownSerializer} with rules-style header and footer.
      class RulesSerializer < BaseProviderSerializer
        # @param context [Hash] The introspection context.
        # @param config [RailsAiBridge::Configuration] The configuration object.
        def initialize(context, config: RailsAiBridge.configuration)
          super
        end

        # @return [String] Markdown for legacy `.cursorrules` (compact) or full Cursor-oriented document (full mode).
        def call
          if @config.context_mode == :full
            MarkdownSerializer.new(context,
                                   header_class: Formatters::Providers::RulesHeaderFormatter,
                                   footer_class: Formatters::Providers::RulesFooterFormatter).call
          else
            render_compact
          end
        end

        private

        # Renders the compact version of the Cursor rules file by delegating to the orchestrator.
        #
        # @return [String] The generated content.
        def render_compact
          RulesOrchestrator.new(context: context, config: @config).call
        end
      end
    end
  end
end
