# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Active Storage section with attachment models and configured services.
      #
      # @see Formatters::Providers::SectionFormatter
      class ActiveStorageFormatter < SectionFormatter
        section :active_storage

        private

        def render(data)
          return unless data[:models]&.any? || data[:services]&.any?

          lines = ['## Active Storage']
          lines << "- Attached to: #{data[:models].map { |m| "`#{m}`" }.join(', ')}" if data[:models]&.any?
          lines << "- Services: #{data[:services].map { |s| "`#{s}`" }.join(', ')}" if data[:services]&.any?
          lines.join("\n")
        end
      end
    end
  end
end
