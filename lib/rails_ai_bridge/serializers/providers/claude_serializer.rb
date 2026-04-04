# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Generates CLAUDE.md optimized for Claude Code.
      # In :compact mode (default), produces ≤150 lines with MCP tool references.
      # In :full mode, delegates to MarkdownSerializer with behavioral rules.
      class ClaudeSerializer < BaseProviderSerializer
        # @param context [Hash] Introspection hash from {Introspector#call}.
        # @param config [RailsAiBridge::Configuration] Bridge configuration.
        def initialize(context, config: RailsAiBridge.configuration)
          super(context, config: config)
        end

        # @return [String] Markdown written to `CLAUDE.md` by {ContextFileSerializer}.
        def call
          if @config.context_mode == :full
            MarkdownSerializer.new(context,
              header_class: Formatters::Providers::ClaudeHeaderFormatter,
              footer_class: Formatters::Providers::ClaudeFooterFormatter
            ).call
          else
            render_compact
          end
        end
      end
    end
  end
end
