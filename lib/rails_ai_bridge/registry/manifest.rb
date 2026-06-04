# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Immutable value object describing a single pack's source and loading behaviour.
    #
    # @!attribute [r] source
    #   @return [String] GitHub source identifier, e.g. "igmarin/ruby-core-skills"
    # @!attribute [r] tile
    #   @return [String] relative path to the pack's tile manifest, usually "tile.json"
    # @!attribute [r] always_loaded
    #   @return [Boolean] whether this pack is unconditionally loaded
    # @!attribute [r] depends_on
    #   @return [Array<String>] names of packs this pack depends on
    PackDefinition = Data.define(:source, :tile, :always_loaded, :depends_on) do
      # @return [Boolean]
      def always_loaded? = always_loaded
    end

    # Immutable value object representing the root registry manifest.
    #
    # @!attribute [r] version
    #   @return [String] manifest schema version
    # @!attribute [r] packs
    #   @return [Hash{String => PackDefinition}] map of pack name to definition
    # @!attribute [r] default_stack
    #   @return [Array<String>] pack names loaded when no framework is detected
    RegistryManifest = Data.define(:version, :packs, :default_stack) do
      # Builds a {RegistryManifest} from a parsed JSON hash.
      #
      # @param hash [Hash] parsed JSON object
      # @return [RegistryManifest]
      def self.from_json(hash)
        packs = (hash['packs'] || {}).transform_values do |pack_hash|
          PackDefinition.new(
            source: pack_hash.fetch('source'),
            tile: pack_hash.fetch('tile'),
            always_loaded: pack_hash.fetch('always_loaded', false),
            depends_on: pack_hash.fetch('depends_on', [])
          )
        end

        new(
          version: hash.fetch('version'),
          packs: packs,
          default_stack: hash.fetch('default_stack', [])
        )
      end

      # Loads and parses a registry manifest from a JSON file on disk.
      #
      # @param path [String] absolute or relative path to the registry JSON file
      # @return [RegistryManifest]
      # @raise [ArgumentError] if the file does not exist
      def self.from_file(path)
        raise ArgumentError, "Registry manifest not found at: #{path}" unless File.exist?(path)

        from_json(JSON.parse(File.read(path)))
      end
    end
  end
end
