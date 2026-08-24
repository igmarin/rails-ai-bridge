# frozen_string_literal: true

module RailsAiBridge
  # Thread-local application scope for the runtime seam.
  #
  # Provides a scoped +with_app(app)+ block so that server tool calls, CLI
  # commands, resources, and tests can share a single app reference without
  # hardcoding +Rails.application+ everywhere. The default falls back to
  # +Rails.application+ for backward compatibility with Rails-hosted usage.
  #
  # @example Scoped execution
  #   RailsAiBridge::AppScope.with_app(my_app) do
  #     RailsAiBridge::AppScope.current_app # => my_app
  #   end
  #   RailsAiBridge::AppScope.current_app   # => Rails.application
  #
  module AppScope
    APP_KEY = :rails_ai_bridge_current_app

    class << self
      # Executes a block with +app+ as the current application for the calling
      # thread. Nested scopes restore the prior app on exit, including when the
      # block raises.
      #
      # @param app [Object] the application to scope
      # @yield block to execute within the app scope
      # @return [Object] the block result
      # :reek:DuplicateMethodCall -- Thread.current access is the established pattern (see Registry.with_request_resolver)
      def with_app(app)
        previous = Thread.current[APP_KEY]
        Thread.current[APP_KEY] = app
        yield
      ensure
        Thread.current[APP_KEY] = previous
      end

      # Returns the current application for the calling thread, defaulting to
      # +Rails.application+ when no scope is active.
      #
      # @return [Object, nil] the current Rails application or scoped app
      def current_app
        Thread.current[APP_KEY] || (defined?(Rails) ? Rails.application : nil)
      end

      # Clears the app scope for the calling thread. Primarily for test cleanup.
      #
      # @return [void]
      def clear_app
        Thread.current[APP_KEY] = nil
      end
    end
  end
end
