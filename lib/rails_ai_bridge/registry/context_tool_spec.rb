# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Immutable value object describing a single tool requested from a context provider.
    #
    # Mirrors the untagged +ContextToolSpec+ enum in the Rust runtime: a spec is
    # either a plain tool name (simple) or a mapping that routes the tool output
    # into a named context field, optionally with arguments (mapped).
    #
    # @!attribute [r] name
    #   @return [String] name of the remote tool to execute
    # @!attribute [r] field
    #   @return [String, nil] target context field for mapped tools; nil for simple tools
    # @!attribute [r] arguments
    #   @return [Hash, nil] optional arguments passed when executing the tool
    ContextToolSpec = Data.define(:name, :field, :arguments) do
      # Builds a {ContextToolSpec} from a parsed JSON value.
      #
      # @param value [String, Hash] plain tool name or mapped tool object
      # @return [ContextToolSpec]
      # @raise [ArgumentError] when the value is neither a String nor a Hash,
      #   or a mapped tool is missing a required field
      def self.from_json(value)
        return new(name: value, field: nil, arguments: nil) if value.is_a?(String)
        return from_mapped_json(value) if value.is_a?(Hash)

        raise ArgumentError, "Context tool spec must be a String or an object, got #{value.class.name}"
      end

      # @return [Boolean] true when the spec is a plain tool name
      # :reek:NilCheck -- value-object predicate over an optional attribute
      def simple? = field.nil?

      # @return [Boolean] true when the spec maps tool output into a context field
      # :reek:NilCheck -- value-object predicate over an optional attribute
      def mapped? = !field.nil?

      # @api private
      def self.from_mapped_json(hash)
        new(
          name: hash.fetch('name'),
          field: hash.fetch('field'),
          arguments: hash['arguments']
        )
      rescue KeyError => error
        raise ArgumentError, "Context tool spec missing required field: #{error.key}"
      end

      private_class_method :from_mapped_json
    end
  end
end
