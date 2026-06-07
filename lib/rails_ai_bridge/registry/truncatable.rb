# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Shared mixin for truncating text and sanitizing markdown for safe output.
    #
    # @example
    #   include Truncatable
    #   truncate('A very long description here', 20) #=> "A very long descript…"
    #   sanitize_markdown("skill | bad\ncontent") #=> "skill \\| bad content"
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

      # Sanitizes a string for safe inline embedding in markdown output.
      #
      # Strips newlines (to prevent header/block injection) and escapes pipe
      # characters (to prevent markdown table structure breakage). Used for
      # skill names, pack names, and descriptions sourced from third-party
      # manifests that may contain adversarial content.
      #
      # @param text [String, nil] the text to sanitize
      # @return [String] sanitized text safe for markdown inline use
      def sanitize_markdown(text)
        text.to_s.gsub(/[\r\n]+/, ' ').gsub('|', '\\|')
      end
    end
  end
end
