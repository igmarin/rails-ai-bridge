# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Single source of truth for the anti-hallucination rules injected into
    # every generated context file (markdown and JSON). Keeps AI assistants
    # verifying against the live application through the `rails_*` MCP tools
    # instead of inventing structure.
    #
    # Controlled by {Config::Output#anti_hallucination_rules} (default +true+).
    #
    # @see SharedAssistantGuidance
    module AntiHallucinationRules
      # Consistent named section heading used across all markdown outputs.
      HEADING = '## Anti-hallucination rules'

      RULES = [
        '- Verify before you write (column, association, route, helper, gem).',
        '- Mark assumptions with `[ASSUMPTION]`. Silent guesses are forbidden.',
        '- This app is not average Rails. Query conventions and gems before scaffolding.',
        '- Check the inheritance chain (filters, concerns, STI) before editing a controller or model.',
        '- Empty tool output is information, not permission to invent.',
        '- Re-query after writes. Stale tool output lies.'
      ].freeze

      class << self
        # @return [Boolean] +true+ when the rules block should be injected
        def enabled?
          RailsAiBridge.configuration.anti_hallucination_rules
        end

        # Rule bullets without the heading.
        #
        # @return [Array<String>] frozen rule lines, empty when disabled
        def rules
          return [].freeze unless enabled?

          RULES
        end

        # Markdown lines for the named section, with a trailing blank line.
        #
        # @return [Array<String>] +[HEADING, '', *RULES, '']+ or +[]+ when disabled
        def markdown_lines
          return [] unless enabled?

          [HEADING, '', *RULES, '']
        end

        # Markdown section as a string, suitable for splicing into a document
        # after the header/intro and before content sections.
        #
        # @return [String, nil] +nil+ when disabled
        def markdown_block
          return nil unless enabled?

          markdown_lines.join("\n").chomp
        end
      end

      # Drop-in section for {MarkdownSerializer}'s formatter pipeline: +filter_map+
      # skips it entirely when the rules are disabled.
      class SectionFormatter
        # @param _context [Hash] unused; the rules are static
        def initialize(_context)
          @block = AntiHallucinationRules.markdown_block
        end

        # @return [String, nil] markdown rules block, or +nil+ when disabled
        def call
          @block
        end
      end
    end
  end
end
