# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Shared mixin for truncating text to a maximum byte length with a Unicode ellipsis.
    #
    # @example
    #   include Truncatable
    #   truncate('A very long description here', 20) #=> "A very long descript…"
    module Truncatable
      # Truncates +text+ to at most +max+ characters, appending +…+ when truncated.
      #
      # @param text [String] the text to truncate
      # @param max [Integer] maximum number of characters (including the ellipsis)
      # @return [String] original text when short enough, or truncated form
      def truncate(text, max)
        return text if text.length <= max

        "#{text[0, max - 1]}…"
      end
    end
  end
end
