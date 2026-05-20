# frozen_string_literal: true

module RailsAiBridge
  # Pre-populates the introspection cache during Rails boot.
  #
  # Calling +.warm+ triggers a full introspection pass so that the first
  # MCP tool call returns instantly from cache rather than blocking on
  # a cold introspection. Errors are logged and swallowed — warming is
  # best-effort and must never prevent the app from starting.
  class CacheWarmer
    class << self
      # Warms the full introspection cache for +app+.
      #
      # @param app [Rails::Application]
      # @return [void]
      def warm(app = Rails.application)
        ContextProvider.fetch(app)
      rescue StandardError => error
        log_warning("cache warming failed: #{error.message}")
      end

      # Warms individual section caches for the given introspector keys.
      #
      # @param sections [Array<Symbol>] introspector keys to warm
      # @param app [Rails::Application]
      # @return [void]
      def warm_sections(sections, app = Rails.application)
        sections.each do |section|
          ContextProvider.fetch_section(section, app)
        rescue StandardError => error
          log_warning("section #{section} warming failed: #{error.message}")
        end
      end

      private

      def log_warning(message)
        Rails.logger&.warn("[rails-ai-bridge] #{message}")
      end
    end
  end
end
