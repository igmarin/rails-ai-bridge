# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Custom Middleware section.
      class MiddlewareFormatter < Base
        # @return [String, nil]
        def call
          data = context[:middleware]
          return unless data
          return if data[:error]

          lines = [ "## Custom Middleware" ]
          if data[:custom_middleware]&.any?
            data[:custom_middleware].each do |m|
              detail = "- `#{m[:class_name]}` (#{m[:file]})"
              detail += " — #{m[:detected_patterns].join(', ')}" if m[:detected_patterns]&.any?
              lines << detail
            end
          else
            lines << "- No custom middleware in app/middleware/"
          end
          lines.join("\n")
        end
      end
    end
  end
end
