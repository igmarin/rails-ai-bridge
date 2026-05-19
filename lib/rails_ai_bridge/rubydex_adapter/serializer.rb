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
        serializer_class = self.class
        hash = serializer_class.base_declaration_hash(decl)
        serializer_class.append_relationships(hash, decl)
        hash.compact
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

      def self.append_relationships(hash, decl)
        hash[:definitions] = definitions_for(decl)
        hash[:ancestors] = ancestor_names_for(decl)
        hash[:descendants] = descendant_names_for(decl)
        hash[:owner] = owner_name_for(decl)
        hash
      end

      def self.definitions_for(decl)
        defs = decl.try(:definitions)
        defs&.map { |defn| definition_to_hash(defn, nil) }
      end

      def self.ancestor_names_for(decl)
        ancs = decl.try(:ancestors)
        ancs&.map(&:name)
      end

      def self.descendant_names_for(decl)
        descs = decl.try(:descendants)
        descs&.map(&:name)
      end

      def self.owner_name_for(decl)
        owner = decl.try(:owner)
        owner&.name
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
