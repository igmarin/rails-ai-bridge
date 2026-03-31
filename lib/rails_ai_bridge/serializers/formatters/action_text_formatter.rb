# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Action Text section with rich text fields.
      class ActionTextFormatter < Base
        # @return [String, nil]
        def call
          data = context[:action_text]
          return unless data
          return if data[:error]
          return unless data[:rich_text_fields]&.any?

          lines = [ "## Action Text" ]
          data[:rich_text_fields].each { |f| lines << "- `#{f[:model]}` has_rich_text :#{f[:field]}" }
          lines.join("\n")
        end
      end
    end
  end
end
