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
        {
          name: decl.name,
          unqualified_name: decl.respond_to?(:unqualified_name) ? decl.unqualified_name : nil,
          type: declaration_type(decl)
        }.compact
      end

      # Converts a rubydex declaration to a serializable hash with full details.
      #
      # Includes definitions, ancestors, descendants, and owner.
      #
      # @param decl [Object] rubydex declaration
      # @return [Hash]
      def detailed_declaration_to_hash(decl)
        hash = {
          name: decl.name,
          unqualified_name: decl.respond_to?(:unqualified_name) ? decl.unqualified_name : nil,
          type: declaration_type(decl)
        }

        hash[:definitions] = decl.definitions.map { |d| definition_to_hash(d) } if decl.respond_to?(:definitions)
        hash[:ancestors] = decl.ancestors.map(&:name) if decl.respond_to?(:ancestors)
        hash[:descendants] = decl.descendants.map(&:name) if decl.respond_to?(:descendants)
        hash[:owner] = decl.owner.name if decl.respond_to?(:member) && decl.respond_to?(:owner) && decl.owner

        hash.compact
      end

      # Converts a rubydex definition to a serializable hash.
      #
      # @param defn [Object] rubydex definition
      # @return [Hash]
      def definition_to_hash(defn)
        hash = { name: defn.name }
        hash[:location] = format_location(defn.location) if defn.respond_to?(:location)
        hash[:comments] = defn.comments if defn.respond_to?(:comments) && defn.comments.present?
        hash[:deprecated] = true if defn.respond_to?(:deprecated?) && defn.deprecated?
        hash.compact
      end

      # Formats a rubydex location into a readable string.
      #
      # @param location [Object] rubydex location object
      # @return [String, nil]
      def format_location(location)
        return nil unless location
        return location.to_s unless location.respond_to?(:path)

        path = location.path
        path = path.sub("#{@root}/", '') if path&.start_with?(@root)
        path
      end

      # Determines the type of a rubydex declaration.
      #
      # @param decl [Object] rubydex declaration
      # @return [String]
      def declaration_type(decl)
        klass = decl.class.name.to_s.split('::').last&.downcase
        case klass
        when /class/ then 'class'
        when /module/ then 'module'
        when /method/ then 'method'
        when /constant/ then 'constant'
        else 'declaration'
        end
      end
    end
  end
end
