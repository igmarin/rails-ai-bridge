# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Application Configuration section.
      #
      # @see Formatters::Providers::SectionFormatter
      class ConfigFormatter < SectionFormatter
        section :config

        private

        def render(data)
          return unless data[:cache_store] || data[:session_store] || data[:timezone] ||
                        data[:middleware_stack]&.any? || data[:initializers]&.any? ||
                        data[:current_attributes]&.any?

          lines = ['## Application Configuration', '']
          lines << "- **Cache store:** `#{data[:cache_store]}`" if data[:cache_store]
          lines << "- **Session store:** `#{data[:session_store]}`" if data[:session_store]
          lines << "- **Timezone:** `#{data[:timezone]}`" if data[:timezone]

          if data[:middleware_stack]&.any?
            lines << '' << '### Middleware Stack'
            data[:middleware_stack].each { |m| lines << "- `#{m}`" }
          end

          if data[:initializers]&.any?
            lines << '' << '### Initializers'
            data[:initializers].each { |i| lines << "- `#{i}`" }
          end

          if data[:current_attributes]&.any?
            lines << '' << '### CurrentAttributes'
            data[:current_attributes].each { |c| lines << "- `#{c}`" }
          end
          lines.join("\n")
        end
      end
    end
  end
end
