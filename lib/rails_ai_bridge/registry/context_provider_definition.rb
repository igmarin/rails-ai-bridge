# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Immutable value object describing a context provider service declared in the
    # registry manifest.
    #
    # Context providers are external services (currently MCP servers) that the
    # bridge can query for project context. This definition is preparatory — the
    # data structures mirror the Rust runtime's manifest format, but no
    # integration consumes them yet.
    #
    # @!attribute [r] type
    #   @return [String] provider type, e.g. "mcp"
    # @!attribute [r] endpoint
    #   @return [String] provider HTTP endpoint base URL
    # @!attribute [r] optional
    #   @return [Boolean] whether the provider may be skipped when unavailable
    # @!attribute [r] tools
    #   @return [Array<ContextToolSpec>] tools requested from the provider
    ContextProviderDefinition = Data.define(:type, :endpoint, :optional, :tools) do
      # Builds a {ContextProviderDefinition} from a parsed JSON hash.
      #
      # @param hash [Hash] parsed JSON object
      # @return [ContextProviderDefinition]
      # @raise [ArgumentError] when a required field is missing
      def self.from_json(hash)
        new(
          type: hash.fetch('type'),
          endpoint: hash.fetch('endpoint'),
          optional: hash.fetch('optional', false),
          tools: (hash['tools'] || []).map { |tool| ContextToolSpec.from_json(tool) }
        )
      rescue KeyError => error
        raise ArgumentError, "Context provider definition missing required field: #{error.key}"
      end

      # @return [Boolean]
      def optional? = optional
    end
  end
end
