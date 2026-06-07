# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Service object responsible for resolving and loading skill packs and registries.
    #
    # Orchestrates the loading of packs from the registry manifest, handling
    # framework auto-detection, explicit pack selection, and local registry overrides.
    # Returns a Resolver instance with all packs loaded and prioritized.
    class PackResolver
      # Pack name constants
      RAILS_PACK = 'rails'
      HANAMI_PACK = 'hanami'
      CORE_PACK = 'core'

      # Priority constants (lower is higher priority)
      PRIORITY_HIGH = 10
      PRIORITY_MEDIUM = 20
      PRIORITY_LOW = 30

      # Creates a new PackResolverService with a reference to a SkillSourceResolver.
      #
      # @param source_resolver [SkillSourceResolver] resolver for remote git sources
      # @param pack_detector [Object] optional pack detector for testing (defaults to PackDetector)
      def initialize(source_resolver, pack_detector = PackDetector)
        @source_resolver = source_resolver
        @pack_detector = pack_detector
      end

      # Resolves active packs from the manifest and custom configuration.
      #
      # This will automatically resolve remote repositories if needed, load the tile
      # manifest configurations, and merge local directory overrides.
      #
      # @param manifest [RegistryManifest] the registry manifest containing pack definitions
      # @param explicit_packs [Array<String>, nil] optional list of pack names to load
      # @param local_registries [Array<String>, nil] optional list of local registry directory paths
      # @return [Resolver] resolver with all active packs loaded
      # :reek:TooManyStatements -- Necessary complexity for pack loading logic
      def resolve(manifest, explicit_packs = nil, local_registries = nil)
        active_pack_names = gather_active_packs(manifest, explicit_packs)
        loaded_packs = load_defined_packs(manifest, active_pack_names)
        load_local_registries(loaded_packs, local_registries)

        Resolver.new(loaded_packs)
      end

      private

      # Gathers the set of pack names that should be loaded.
      #
      # Combines always_loaded packs with either explicit_packs or auto-detected framework packs.
      #
      # @param manifest [RegistryManifest] the registry manifest
      # @param explicit_packs [Array<String>, nil] optional explicit pack names
      # @return [Set<String>] set of pack names to load
      # :reek:TooManyStatements -- Necessary complexity for pack gathering logic
      def gather_active_packs(manifest, explicit_packs)
        active_pack_names = Set.new

        # 1. Gather packs marked as always_loaded
        manifest.packs.each do |name, pack_def|
          active_pack_names.add(name) if pack_def.always_loaded?
        end

        # 2. Add explicit packs or perform framework auto-detection
        if explicit_packs
          explicit_packs.each { |p| active_pack_names.add(p) }
        else
          detected = @pack_detector.detect
          if detected.empty?
            # No framework detected, load default stack
            manifest.default_stack.each { |p| active_pack_names.add(p) }
          else
            # Auto-detect frameworks
            detected.each do |framework|
              case framework
              when DetectedFramework::Rails
                active_pack_names.add(RAILS_PACK)
              when DetectedFramework::Hanami
                active_pack_names.add(HANAMI_PACK)
              end
            end
          end
        end

        active_pack_names
      end

      # Loads defined packs from the manifest.
      #
      # Resolves each pack via the source resolver, loads its tile manifest,
      # and assigns priority based on pack name.
      #
      # @param manifest [RegistryManifest] the registry manifest
      # @param active_pack_names [Set<String>] set of pack names to load
      # @return [Array<LoadedPack>] array of loaded packs
      def load_defined_packs(manifest, active_pack_names)
        loaded_packs = []

        active_pack_names.each do |name|
          pack_def = manifest.packs[name]
          raise "Pack '#{name}' not defined in registry manifest" unless pack_def

          base_path = @source_resolver.resolve(pack_def.source)
          tile_path = File.join(base_path, pack_def.tile)

          raise "Failed to read tile manifest for pack '#{name}' at #{tile_path}" unless File.exist?(tile_path)

          tile = TileManifest.from_file(tile_path)
          priority = compute_priority(name)

          loaded_packs << LoadedPack.new(
            name: name,
            tile: tile,
            base_path: base_path,
            priority: priority
          )
        end

        loaded_packs
      end

      # Loads local registry directories.
      #
      # Loads tile manifests from local directories and assigns them priority 0.
      #
      # @param loaded_packs [Array<LoadedPack>] array of existing loaded packs
      # @param local_registries [Array<String>, nil] optional local registry paths
      # @return [Array<LoadedPack>] array of loaded packs including local registries
      def load_local_registries(loaded_packs, local_registries)
        return loaded_packs unless local_registries

        local_registries.each_with_index do |path, i|
          tile_path = File.join(path, 'tile.json')

          raise "Failed to read local registry tile manifest at #{tile_path}" unless File.exist?(tile_path)

          tile = TileManifest.from_file(tile_path)

          loaded_packs << LoadedPack.new(
            name: "local_#{i}",
            tile: tile,
            base_path: path,
            priority: 0 # Highest priority
          )
        end

        loaded_packs
      end

      # Computes priority for a pack based on its name.
      #
      # @param name [String] pack name
      # @return [Integer] priority value (lower is higher priority)
      def compute_priority(name)
        case name
        when RAILS_PACK, HANAMI_PACK
          PRIORITY_HIGH
        when CORE_PACK
          PRIORITY_MEDIUM
        else
          PRIORITY_LOW
        end
      end
    end
  end
end
