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
      attr_reader :resolver_ttl

      # @return [Integer] TTL in seconds between git pull refreshes per cached pack (default: 86400 = 24 h).
      #   Set to 0 to pull on every resolver rebuild. Skill pack files are documentation and rarely
      #   change between releases, so a long freshness window is appropriate.
      attr_accessor :git_pull_ttl

      # @return [Integer] timeout in seconds for individual git operations (clone, pull, checkout).
      #   Prevents a slow or unreachable remote from blocking the calling thread indefinitely.
      attr_accessor :git_timeout

      # Sets the in-memory resolver cache TTL.
      #
      # Coerces the value to a non-negative integer; raises +ArgumentError+ for
      # non-numeric or negative inputs to prevent silent +TypeError+ in
      # {ResolverCache#expired?} when nil or strings are assigned.
      #
      # @param value [Integer, #to_i] cache TTL in seconds; 0 disables caching
      # @raise [ArgumentError] if value cannot be coerced to a non-negative integer
      def resolver_ttl=(value)
        int = Integer(value)
        raise ArgumentError, "resolver_ttl must be >= 0, got #{int}" if int.negative?

        @resolver_ttl = int
      rescue ArgumentError, TypeError
        raise ArgumentError, "resolver_ttl must be a non-negative integer, got #{value.inspect}"
      end

      def initialize
        @registry_manifest_path = 'config/rails_ai_bridge_registry.json'
        @skill_cache_dir = File.expand_path('~/.rails-ai-bridge/cache')
        @skill_packs = nil
        @local_registry_paths = []
        @resolver_ttl = 1800
        @git_pull_ttl = 86_400
        @git_timeout = 30
      end
    end
  end
end
