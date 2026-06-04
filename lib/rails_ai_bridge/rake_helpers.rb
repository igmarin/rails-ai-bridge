# frozen_string_literal: true

module RailsAiBridge
  # Helper methods for Rake tasks to avoid polluting the global namespace.
  module RakeHelpers
    # Builds a registry resolver from the current configuration.
    #
    # @return [RailsAiBridge::Registry::Resolver, nil] resolver instance or nil if configuration is invalid
    def self.build_registry_resolver
      extend Registry::ResolverBuilder

      build_resolver(RailsAiBridge.configuration)
    end
  end
end
