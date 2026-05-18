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
        base_declaration_hash(decl).compact
      end

      # Converts a rubydex declaration to a serializable hash with full details.
      #
      # Includes definitions, ancestors, descendants, and owner.
      #
      # @param decl [Object] rubydex declaration
      # @return [Hash]
      def detailed_declaration_to_hash(decl)
        hash = base_declaration_hash(decl)
        append_relationships(hash, decl)
        hash.compact
      end

      # Converts a rubydex definition to a serializable hash.
      #
      # @param defn [Object] rubydex definition
      # @return [Hash]
      def definition_to_hash(defn)
        hash = { name: defn.name }
        hash[:location] = format_location(defn.location) if defn.respond_to?(:location)
        defn_comments = safe_send(defn, :comments)
        hash[:comments] = defn_comments if defn_comments.present?
        hash[:deprecated] = true if safe_send(defn, :deprecated?)
        hash.compact
      end

      # Formats a rubydex location into a readable string.
      #
      # @param location [Object] rubydex location object
      # @return [String, nil]
      def format_location(location)
        return nil unless location
        return location.to_s unless location.respond_to?(:path)

        relativize_path(location.path)
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

      private

      def base_declaration_hash(decl)
        {
          name: decl.name,
          unqualified_name: safe_send(decl, :unqualified_name),
          type: declaration_type(decl)
        }
      end

      def append_relationships(hash, decl)
        hash[:definitions] = decl.definitions.map { |defn| definition_to_hash(defn) } if decl.respond_to?(:definitions)
        hash[:ancestors] = decl.ancestors.map(&:name) if decl.respond_to?(:ancestors)
        hash[:descendants] = decl.descendants.map(&:name) if decl.respond_to?(:descendants)
        owner = decl.respond_to?(:member) && decl.respond_to?(:owner) ? decl.owner : nil
        hash[:owner] = owner.name if owner
      end

      def safe_send(obj, method)
        obj.respond_to?(method) ? obj.send(method) : nil
      end

      def relativize_path(path)
        return path unless path&.start_with?(@root)

        path.sub("#{@root}/", '')
      end
    end
  end
end
