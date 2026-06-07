# frozen_string_literal: true

module RailsAiBridge
  module Config
    # Holds registry resolution configuration for skill packs.
    #
    # Controls how the bridge resolves and loads skill packs from git repositories,
    # including cache location, manifest path, explicit pack selection, and local
    # registry overrides.
    #
    # @see RailsAiBridge::Registry::PackResolver
    # @see RailsAiBridge::Registry::Resolver
    class Registry
      # @return [String] path to the registry manifest JSON file
      attr_accessor :registry_manifest_path

      # @return [String] directory for caching git repositories
      attr_accessor :skill_cache_dir

      # @return [Array<String>, nil] explicit pack names to load, or nil for auto-detection
      attr_accessor :skill_packs

      # @return [Array<String>] local registry directory paths
      attr_accessor :local_registry_paths

      # @return [Integer] TTL in seconds for the in-memory resolver cache (default: 1800 = 30 min)
      attr_accessor :resolver_ttl

      def initialize
        @registry_manifest_path = 'config/rails_ai_bridge_registry.json'
        @skill_cache_dir = File.expand_path('~/.rails-ai-bridge/cache')
        @skill_packs = nil
        @local_registry_paths = []
        @resolver_ttl = 1800
      end
    end
  end
end
