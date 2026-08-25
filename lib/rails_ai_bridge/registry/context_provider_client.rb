# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Performs one provider exchange through an MCP HTTP transport.
    #
    # The client owns policy verification, remote tool metadata checks,
    # result normalization, and safe error translation. It never stores
    # credentials and closes the transport in an ensure block.
    class ContextProviderClient
      # Result of a single provider tool call.
      #
      # @!attribute status
      #   @return [Symbol] one of :success, :partial_failure, :error
      # @!attribute content
      #   @return [Object, nil] normalized tool result content when successful
      # @!attribute provenance
      #   @return [String, nil] provider identity and source status label
      # @!attribute error
      #   @return [ContextProviderError, nil] typed error when not successful
      Result = Struct.new(:status, :content, :provenance, :error, keyword_init: true)

      # @param provider [ContextProviderDefinition] provider manifest
      # @param policy [EndpointPolicy] policy used to validate the endpoint
      # @param transport_factory [#call] callable returning an MCP transport
      # @param auth_resolver [Proc, nil] callable returning auth headers for the provider
      # @return [ContextProviderClient]
      def initialize(provider:, policy:, transport_factory:, auth_resolver:)
        @provider = provider
        @policy = policy
        @transport_factory = transport_factory
        @auth_resolver = auth_resolver
      end

      # Calls a single remote tool and returns a typed result.
      #
      # @param tool_name [String] name of the tool to call
      # @param arguments [Hash] tool arguments
      # @return [Result]
      def call_tool(tool_name, arguments: {})
        policy_result = @policy.call(@provider.endpoint)
        return Result.new(status: :error, error: policy_result.error) unless policy_result.success?

        transport = nil
        begin
          headers = @auth_resolver ? @auth_resolver.call(@provider.endpoint, policy_result.uri) : {}
          transport = @transport_factory.call(policy_result.uri, policy_result.addresses, headers)
          remote_tool = find_tool(transport, tool_name)
          return Result.new(status: :error, error: RemoteToolError.new("tool #{tool_name.inspect} is not allowed")) unless remote_tool

          content = transport.call_tool(name: tool_name, arguments: arguments)
          Result.new(status: :success, content: content, provenance: provenance_for(policy_result.uri), error: nil)
        rescue RailsAiBridge::Registry::ContextProviderError => error
          Result.new(status: :error, error: error)
        rescue StandardError => error
          Result.new(status: :error, error: ConnectionError.new("provider call failed (#{error.class})"))
        ensure
          close_transport(transport)
        end
      end

      private

      # @param transport [Object, nil] the active transport
      # @return [void]
      def close_transport(transport)
        transport&.close
      rescue StandardError
        nil
      end

      # @param transport [#tools] the active transport
      # @param tool_name [String]
      # @return [Object, nil] the remote tool metadata object, or nil if not allowed
      def find_tool(transport, tool_name)
        transport.tools.find do |tool|
          tool.name == tool_name && tool.read_only_hint && !tool.destructive_hint
        end
      end

      # @param uri [URI]
      # @return [String] a safe provenance label with no credentials
      def provenance_for(uri)
        "#{uri.scheme}://#{uri.host}"
      end
    end
  end
end
