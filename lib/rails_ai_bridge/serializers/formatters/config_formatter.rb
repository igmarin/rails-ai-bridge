# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Configuration section with cache, session, and timezone.
      class ConfigFormatter < SectionFormatter
        section :config

        private

        def render(data)
          lines = [ "## Configuration" ]
          lines << "- Cache store: #{data[:cache_store]}" if data[:cache_store]
          lines << "- Session store: #{data[:session_store]}" if data[:session_store]
          lines << "- Timezone: #{data[:timezone]}" if data[:timezone].present?
          lines << "- Initializers: #{data[:initializers].join(', ')}" if data[:initializers]&.any?
          lines.join("\n")
        end
      end
    end
  end
end
