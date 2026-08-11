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
    # @!attribute [r] context_providers
    #   @return [Hash{String => ContextProviderDefinition}] context providers keyed by name
    RegistryManifest = Data.define(:version, :packs, :default_stack, :context_providers) do
      # Backward-compatible constructor: +context_providers+ defaults to an empty
      # hash so manifests built before context provider support keep working.
      def initialize(version:, packs:, default_stack:, context_providers: {})
        super
      end

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
          default_stack: hash.fetch('default_stack', []),
          context_providers: parse_context_providers(hash['context_providers'] || {})
        )
      rescue KeyError => error
        raise ArgumentError, "Registry manifest missing required field: #{error.key}"
      end

      # Loads and parses a registry manifest from a JSON file on disk.
      #
      # @param path [String] absolute or relative path to the registry JSON file
      # @return [RegistryManifest]
      # @raise [ArgumentError] if the file does not exist, cannot be read, or contains malformed JSON
      def self.from_file(path)
        from_json(JSON.parse(File.read(path)))
      rescue JSON::ParserError => error
        raise ArgumentError, "Registry manifest at '#{path}' contains invalid JSON: #{error.message}"
      rescue SystemCallError => error
        raise ArgumentError, "Registry manifest at '#{path}' could not be read: #{error.message}"
      end

      # @api private
      def self.parse_context_providers(providers_hash)
        providers_hash.transform_values { |provider_data| ContextProviderDefinition.from_json(provider_data) }
      end

      private_class_method :parse_context_providers
    end

    # Validation API lives in a reopened class body rather than in the
    # +Data.define+ block: constant declarations inside a +Data.define+ block
    # resolve lexically into the surrounding +Registry+ module, so a nested
    # +ValidationError+ could neither be defined on the Data class nor
    # referenced by bare name from methods defined in that block.
    class RegistryManifest
      # Raised by {.validate!} when the manifest structure is invalid.
      class ValidationError < StandardError; end

      # Validates the structure of a parsed registry manifest hash.
      #
      # An empty manifest is valid (no required top-level keys). When present,
      # known keys are type-checked: +version+ (String), +default_stack+
      # (Array of Strings), and +packs+ (Hash of pack name to definition with a
      # required non-empty String +source+). Unknown keys are ignored so future
      # manifest fields do not break older validators.
      #
      # @param data [Object] parsed JSON value to validate
      # @return [Hash] the validated data, unchanged
      # @raise [ValidationError] with a message describing the first invalid field
      def self.validate!(data)
        raise ValidationError, 'Registry manifest root must be a JSON object (Hash)' unless data.is_a?(Hash)

        validate_version!(data) if data.key?('version')
        validate_default_stack!(data) if data.key?('default_stack')
        validate_packs!(data) if data.key?('packs')
        data
      end

      class << self
        private

        def validate_version!(data)
          version = data['version']
          return if version.is_a?(String)

          raise ValidationError, "'version' must be a String (got #{type_name(version)})"
        end

        def validate_default_stack!(data)
          stack = data['default_stack']
          return if stack.is_a?(Array) && stack.all?(String)

          raise ValidationError, "'default_stack' must be an Array of Strings"
        end

        def validate_packs!(data)
          packs = data['packs']
          raise ValidationError, "'packs' must be a Hash (got #{type_name(packs)})" unless packs.is_a?(Hash)

          packs.each { |name, pack| validate_pack!(name, pack) }
        end

        # :reek:TooManyStatements -- one guard clause per manifest field; further extraction would obscure the schema
        def validate_pack!(name, pack)
          raise ValidationError, "pack '#{name}' must be a JSON object (Hash), got #{type_name(pack)}" unless pack.is_a?(Hash)

          validate_pack_source!(name, pack)
          validate_pack_string_field!(name, pack, 'ref')
          validate_pack_string_field!(name, pack, 'tile')
          validate_pack_string_array_field!(name, pack, 'depends_on')
          validate_pack_boolean_field!(name, pack, 'always_loaded')
          validate_pack_integer_field!(name, pack, 'priority')
        end

        def validate_pack_source!(name, pack)
          raise ValidationError, "pack '#{name}' is missing required key 'source'" unless pack.key?('source')

          source = pack['source']
          raise ValidationError, "pack '#{name}': 'source' must be a String (got #{type_name(source)})" unless source.is_a?(String)
          return unless source.strip.empty?

          raise ValidationError, "pack '#{name}': 'source' must be a non-empty String"
        end

        # :reek:NilCheck -- optional string fields legitimately accept an explicit null
        def validate_pack_string_field!(name, pack, key)
          return unless pack.key?(key)

          value = pack[key]
          return if value.nil? || value.is_a?(String)

          raise ValidationError, "pack '#{name}': '#{key}' must be a String (got #{type_name(value)})"
        end

        def validate_pack_string_array_field!(name, pack, key)
          return unless pack.key?(key)

          value = pack[key]
          raise ValidationError, "pack '#{name}': '#{key}' must be an Array of Strings (got #{type_name(value)})" unless value.is_a?(Array)
          return if value.all?(String)

          raise ValidationError, "pack '#{name}': '#{key}' must be an Array of Strings"
        end

        def validate_pack_boolean_field!(name, pack, key)
          return unless pack.key?(key)

          value = pack[key]
          return if [true, false].include?(value)

          raise ValidationError, "pack '#{name}': '#{key}' must be a boolean (got #{type_name(value)})"
        end

        def validate_pack_integer_field!(name, pack, key)
          return unless pack.key?(key)

          value = pack[key]
          return if value.is_a?(Integer)

          raise ValidationError, "pack '#{name}': '#{key}' must be an Integer (got #{type_name(value)})"
        end

        def type_name(value)
          value.class.name
        end
      end
    end

    # Validation API lives in a reopened class body rather than in the
    # +Data.define+ block: constant declarations inside a +Data.define+ block
    # resolve lexically into the surrounding +Registry+ module, so a nested
    # +ValidationError+ could neither be defined on the Data class nor
    # referenced by bare name from methods defined in that block.
    class RegistryManifest
      # Raised by {.validate!} when the manifest structure is invalid.
      class ValidationError < StandardError; end

      # Validates the structure of a parsed registry manifest hash.
      #
      # An empty manifest is valid (no required top-level keys). When present,
      # known keys are type-checked: +version+ (String), +default_stack+
      # (Array of Strings), and +packs+ (Hash of pack name to definition with a
      # required non-empty String +source+). Unknown keys are ignored so future
      # manifest fields do not break older validators.
      #
      # @param data [Object] parsed JSON value to validate
      # @return [Hash] the validated data, unchanged
      # @raise [ValidationError] with a message describing the first invalid field
      def self.validate!(data)
        raise ValidationError, 'Registry manifest root must be a JSON object (Hash)' unless data.is_a?(Hash)

        validate_version!(data) if data.key?('version')
        validate_default_stack!(data) if data.key?('default_stack')
        validate_packs!(data) if data.key?('packs')
        data
      end

      class << self
        private

        def validate_version!(data)
          version = data['version']
          return if version.is_a?(String)

          raise ValidationError, "'version' must be a String (got #{type_name(version)})"
        end

        def validate_default_stack!(data)
          stack = data['default_stack']
          return if stack.is_a?(Array) && stack.all?(String)

          raise ValidationError, "'default_stack' must be an Array of Strings"
        end

        def validate_packs!(data)
          packs = data['packs']
          raise ValidationError, "'packs' must be a Hash (got #{type_name(packs)})" unless packs.is_a?(Hash)

          packs.each { |name, pack| validate_pack!(name, pack) }
        end

        # :reek:TooManyStatements -- one guard clause per manifest field; further extraction would obscure the schema
        def validate_pack!(name, pack)
          raise ValidationError, "pack '#{name}' must be a JSON object (Hash), got #{type_name(pack)}" unless pack.is_a?(Hash)

          validate_pack_source!(name, pack)
          validate_pack_string_field!(name, pack, 'ref')
          validate_pack_string_field!(name, pack, 'tile')
          validate_pack_string_array_field!(name, pack, 'depends_on')
          validate_pack_boolean_field!(name, pack, 'always_loaded')
          validate_pack_integer_field!(name, pack, 'priority')
        end

        def validate_pack_source!(name, pack)
          raise ValidationError, "pack '#{name}' is missing required key 'source'" unless pack.key?('source')

          source = pack['source']
          raise ValidationError, "pack '#{name}': 'source' must be a String (got #{type_name(source)})" unless source.is_a?(String)
          return unless source.strip.empty?

          raise ValidationError, "pack '#{name}': 'source' must be a non-empty String"
        end

        # :reek:NilCheck -- optional string fields legitimately accept an explicit null
        def validate_pack_string_field!(name, pack, key)
          return unless pack.key?(key)

          value = pack[key]
          return if value.nil? || value.is_a?(String)

          raise ValidationError, "pack '#{name}': '#{key}' must be a String (got #{type_name(value)})"
        end

        def validate_pack_string_array_field!(name, pack, key)
          return unless pack.key?(key)

          value = pack[key]
          raise ValidationError, "pack '#{name}': '#{key}' must be an Array of Strings (got #{type_name(value)})" unless value.is_a?(Array)
          return if value.all?(String)

          raise ValidationError, "pack '#{name}': '#{key}' must be an Array of Strings"
        end

        def validate_pack_boolean_field!(name, pack, key)
          return unless pack.key?(key)

          value = pack[key]
          return if [true, false].include?(value)

          raise ValidationError, "pack '#{name}': '#{key}' must be a boolean (got #{type_name(value)})"
        end

        def validate_pack_integer_field!(name, pack, key)
          return unless pack.key?(key)

          value = pack[key]
          return if value.is_a?(Integer)

          raise ValidationError, "pack '#{name}': '#{key}' must be an Integer (got #{type_name(value)})"
        end

        def type_name(value)
          value.class.name
        end
      end
    end
  end
end
