# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module AntiHallucinationRules
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
