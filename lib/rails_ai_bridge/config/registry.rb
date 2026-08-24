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
      # Default path for the registry manifest (4.2.0+ standard location).
      DEFAULT_REGISTRY_MANIFEST_PATH = 'config/rails_ai_bridge/registry.json'

      # Legacy manifest path used before 4.2.0; kept for backward-compat fallback.
      LEGACY_REGISTRY_MANIFEST_PATH = 'config/rails_ai_bridge_registry.json'

      # Default path for the skill pack lockfile (4.2.0+ standard location).
      DEFAULT_LOCKFILE_PATH = 'config/rails_ai_bridge/registry.lock'

      # Legacy lockfile path used before 4.2.0; kept for backward-compat fallback.
      LEGACY_LOCKFILE_PATH = 'config/rails_ai_bridge/directory.lock'

      # @return [String] path to the registry manifest JSON file
      attr_writer :registry_manifest_path

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
      attr_reader :git_pull_ttl

      # @return [Integer] timeout in seconds for individual git operations (clone, pull, checkout).
      #   Prevents a slow or unreachable remote from blocking the calling thread indefinitely.
      attr_reader :git_timeout

      # @return [String, nil] path to the skill pack lockfile. nil disables lockfile verification.
      attr_writer :lockfile_path

      # Returns the configured registry manifest path, applying a backward-compatibility
      # fallback when the default path does not exist but the legacy path does.
      #
      # @return [String] resolved manifest path
      def registry_manifest_path
        return @registry_manifest_path unless @registry_manifest_path == DEFAULT_REGISTRY_MANIFEST_PATH

        File.exist?(DEFAULT_REGISTRY_MANIFEST_PATH) ? DEFAULT_REGISTRY_MANIFEST_PATH : legacy_manifest_path
      end

      # Returns the configured lockfile path, applying a backward-compatibility
      # fallback when the default path does not exist but the legacy path does.
      # Returns +nil+ when lockfile verification is disabled.
      #
      # @return [String, nil] resolved lockfile path
      def lockfile_path
        return @lockfile_path unless @lockfile_path == DEFAULT_LOCKFILE_PATH

        File.exist?(DEFAULT_LOCKFILE_PATH) ? DEFAULT_LOCKFILE_PATH : legacy_lockfile_path
      end

      # @api private
      def legacy_manifest_path
        File.exist?(LEGACY_REGISTRY_MANIFEST_PATH) ? LEGACY_REGISTRY_MANIFEST_PATH : DEFAULT_REGISTRY_MANIFEST_PATH
      end

      # @api private
      def legacy_lockfile_path
        File.exist?(LEGACY_LOCKFILE_PATH) ? LEGACY_LOCKFILE_PATH : DEFAULT_LOCKFILE_PATH
      end

      # @return [Symbol] how to behave when the lockfile differs from the resolved pack:
      #   :strict (default) raises, :warn logs but proceeds, :disabled skips verification.
      attr_accessor :lockfile_verification

      # @return [Boolean] whether declared +depends_on+ packs are loaded transitively
      #   (default: false — dependencies must be listed explicitly and missing ones only warn)
      attr_accessor :auto_load_dependencies

      # Sets the git pull TTL.
      #
      # Coerces the value to a non-negative integer; raises +ArgumentError+ for
      # non-numeric or negative inputs.
      #
      # @param value [Integer, #to_i] pull refresh interval in seconds; 0 pulls on every rebuild
      # @raise [ArgumentError] if value cannot be coerced to a non-negative integer
      def git_pull_ttl=(value)
        int = coerce_integer(value, 'git_pull_ttl')
        raise ArgumentError, "git_pull_ttl must be >= 0, got #{int}" if int.negative?

        @git_pull_ttl = int
      end

      # Sets the git operation timeout.
      #
      # Coerces the value to a positive integer (must be >= 1); raises +ArgumentError+
      # for non-numeric, zero, or negative inputs because a zero-second timeout is
      # never useful and would cause every git operation to fail immediately.
      #
      # @param value [Integer, #to_i] timeout in seconds
      # @raise [ArgumentError] if value cannot be coerced to a positive integer
      def git_timeout=(value)
        int = coerce_integer(value, 'git_timeout', 'positive integer')
        raise ArgumentError, "git_timeout must be >= 1, got #{int}" unless int >= 1

        @git_timeout = int
      end

      # Sets the in-memory resolver cache TTL.
      #
      # Coerces the value to a non-negative integer; raises +ArgumentError+ for
      # non-numeric or negative inputs to prevent silent +TypeError+ in
      # {ResolverCache#expired?} when nil or strings are assigned.
      #
      # @param value [Integer, #to_i] cache TTL in seconds; 0 disables caching
      # @raise [ArgumentError] if value cannot be coerced to a non-negative integer
      def resolver_ttl=(value)
        int = coerce_integer(value, 'resolver_ttl')
        raise ArgumentError, "resolver_ttl must be >= 0, got #{int}" if int.negative?

        @resolver_ttl = int
      end

      def initialize
        @registry_manifest_path = DEFAULT_REGISTRY_MANIFEST_PATH
        @skill_cache_dir = File.expand_path('~/.rails-ai-bridge/cache')
        @skill_packs = nil
        @local_registry_paths = []
        @resolver_ttl = 1800
        @git_pull_ttl = 86_400
        @git_timeout = 30
        @lockfile_path = DEFAULT_LOCKFILE_PATH
        @lockfile_verification = :strict
        @auto_load_dependencies = false
      end

      private

      # Coerces +value+ to an Integer via +Integer()+, raising a consistent
      # +ArgumentError+ when the value cannot be coerced.
      #
      # Extracted from the individual setters so the +rescue+ only catches
      # coercion failures — not the range-validation raises that follow.
      #
      # @param value [Object] value to coerce
      # @param field [String] field name for the error message
      # @param requirement [String] requirement label for the error message
      # @return [Integer]
      # @raise [ArgumentError] if +value+ cannot be coerced to an Integer
      def coerce_integer(value, field, requirement = 'non-negative integer')
        Integer(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{field} must be a #{requirement}, got #{value.inspect}"
      end
    end
  end
end
