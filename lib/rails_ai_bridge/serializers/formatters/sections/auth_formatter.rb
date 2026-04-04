# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Authentication & Authorization section.
      #
      # @see Formatters::Providers::SectionFormatter
      class AuthFormatter < SectionFormatter
        section :auth

        private

        def render(data)
          return unless data[:strategies]&.any? || data[:models]&.any?

          lines = [ "## Authentication (AuthN/AuthZ)" ]
          if data[:strategies]&.any?
            lines << "- Strategies: #{data[:strategies].map { |s| "`#{s}`" }.join(", ")}"
          end
          if data[:models]&.any?
            lines << "- AuthN models: #{data[:models].map { |m| "`#{m}`" }.join(", ")}"
          end
          lines.join("\n")
        end
      end
    end
  end
end
