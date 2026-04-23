# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Custom Middleware section.
      #
      # @see Formatters::Providers::SectionFormatter
      class MiddlewareFormatter < SectionFormatter
        section :middleware

        private

        def render(data)
          lines = ['## Custom Middleware']
          if data[:custom_middleware]&.any?
            data[:custom_middleware].each do |m|
              detail = "- `#{m[:class_name]}` (#{m[:file]})"
              detail += " — #{m[:detected_patterns].join(', ')}" if m[:detected_patterns]&.any?
              lines << detail
            end
          else
            lines << '- No custom middleware in app/middleware/'
          end
          lines.join("\n")
        end
      end
    end
  end
end
