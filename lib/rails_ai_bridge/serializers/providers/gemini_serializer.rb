# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates `GEMINI.md` optimized for Gemini.
      # In +:compact+ mode (default), produces bounded output with MCP tool references.
      # In +:full+ mode, delegates to {MarkdownSerializer} with Gemini header and footer formatters.
      class GeminiSerializer < BaseProviderSerializer
        # @param context [Hash] Introspection hash from {Introspector#call}.
        # @param config [RailsAiBridge::Configuration] Bridge configuration.
        def initialize(context, config: RailsAiBridge.configuration)
          super(context, config: config)
        end

        # @return [String] Markdown written to `GEMINI.md` by {ContextFileSerializer}.
        def call
          if @config.context_mode == :full
            MarkdownSerializer.new(context,
              header_class: Formatters::GeminiHeaderFormatter,
              footer_class: Formatters::GeminiFooterFormatter
            ).call
          else
            render_compact
          end
        end
      end
    end
  end
end
