# frozen_string_literal: true

module RailsAiBridge
  module Registry
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
            tile: pack_hash.fetch('tile', 'directory.json'),
            always_loaded: pack_hash.fetch('always_loaded', false),
            depends_on: pack_hash.fetch('depends_on', []),
            ref: pack_hash.fetch('ref', nil)
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
      # @raise [ArgumentError] if the file does not exist or contains malformed JSON
      def self.from_file(path)
        raise ArgumentError, "Registry manifest not found at: #{path}" unless File.exist?(path)

        from_json(JSON.parse(File.read(path)))
      rescue JSON::ParserError => error
        raise ArgumentError, "Registry manifest at '#{path}' contains invalid JSON: #{error.message}"
      end
    end
  end
end
