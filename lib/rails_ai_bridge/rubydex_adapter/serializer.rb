# frozen_string_literal: true

module RailsAiBridge
  class RubydexAdapter
    # Converts rubydex API objects to serializable Ruby hashes.
    #
    # All methods are idempotent, handle missing attributes gracefully,
    # and never raise.
    class Serializer
      # @param root [String] the project root directory path
      def initialize(root)
        @root = root
      end

      # Converts a rubydex declaration to a serializable hash (summary).
      #
      # @param decl [Object] rubydex declaration
      # @return [Hash]
      def declaration_to_hash(decl)
        self.class.base_declaration_hash(decl).compact
      end

      # Converts a rubydex declaration to a serializable hash with full details.
      #
      # Includes definitions, ancestors, descendants, and owner.
      #
      # @param decl [Object] rubydex declaration
      # @return [Hash]
      def detailed_declaration_to_hash(decl)
        DetailedDeclarationMapper.new(decl, @root).to_h
      end

      # Handles mapping of a rubydex declaration to a detailed hash to avoid Feature Envy.
      class DetailedDeclarationMapper
        def initialize(decl, root)
          @decl = decl
          @root = root
        end

        def to_h
          Serializer.base_declaration_hash(@decl).merge(
            definitions: mapped_definitions,
            ancestors: mapped_names(:ancestors),
            descendants: mapped_names(:descendants),
            owner: @decl.try(:owner)&.name
          ).compact
        end

        private

        def mapped_definitions
          @decl.try(:definitions)&.map { |defn| Serializer.definition_to_hash(defn, @root) }
        end

        def mapped_names(relation)
          @decl.try(relation)&.map(&:name)
        end
      end

      # Converts a rubydex definition to a serializable hash.
      #
      # @param defn [Object] rubydex definition
      # @return [Hash]
      def definition_to_hash(defn)
        self.class.definition_to_hash(defn, @root)
      end

      # Formats a rubydex location into a readable string.
      #
      # @param location [Object] rubydex location object
      # @return [String, nil]
      def format_location(location)
        self.class.format_location(location, @root)
      end

      # Determines the type of a rubydex declaration.
      #
      # @param decl [Object] rubydex declaration
      # @return [String]
      delegate :declaration_type, to: :class

      def self.base_declaration_hash(decl)
        {
          name: decl.name,
          unqualified_name: decl.try(:unqualified_name),
          type: declaration_type(decl)
        }
      end

      def self.definition_to_hash(defn, root)
        {
          name: defn.name,
          location: format_location(defn.try(:location), root),
          comments: defn.try(:comments).presence,
          deprecated: defn.try(:deprecated?) || nil
        }.compact
      end

      def self.format_location(location, root)
        return nil unless location

        path = location.try(:path)
        return location.to_s unless path

        relativize_path(path, root)
      end

      def self.declaration_type(decl)
        klass = class_name(decl)
        TYPE_PATTERNS.each do |type, pattern|
          return type if klass.match?(pattern)
        end
        'declaration'
      end

      TYPE_PATTERNS = {
        'class' => /class/,
        'module' => /module/,
        'method' => /method/,
        'constant' => /constant/
      }.freeze

      def self.class_name(decl)
        decl.class.name.to_s.split('::').last&.downcase
      end

      def self.relativize_path(path, root)
        return path unless root && path&.start_with?(root)

        path.sub("#{root}/", '')
      end
    end
  end
end
