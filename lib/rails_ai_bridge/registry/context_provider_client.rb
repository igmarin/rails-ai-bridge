# frozen_string_literal: true

require 'timeout'

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
      #   @return [Symbol] one of :success, :error
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
        endpoint = @provider.endpoint
        transport = nil
        tool_label = tool_name.inspect
        begin
          policy_result = @policy.call(endpoint)
          return Result.new(status: :error, error: policy_result.error) unless policy_result.success?

          return Result.new(status: :error, error: RemoteToolError.new("tool #{tool_label} is not declared in the provider manifest")) unless tool_declared?(tool_name)

          canonical_uri = policy_result.uri
          headers = resolve_auth(endpoint, canonical_uri)
          transport = @transport_factory.call(canonical_uri, policy_result.addresses, headers)
          remote_tool = find_tool(transport, tool_name)
          return Result.new(status: :error, error: RemoteToolError.new("tool #{tool_label} is not allowed")) unless remote_tool

          content = transport.call_tool(name: tool_name, arguments: arguments)
          Result.new(status: :success, content: content, provenance: provenance_for(canonical_uri), error: nil)
        rescue RailsAiBridge::Registry::ContextProviderError => error
          Result.new(status: :error, error: error)
        rescue Timeout::Error
          Result.new(status: :error, error: RailsAiBridge::Registry::TimeoutError.new('provider call timed out'))
        rescue StandardError => error
          Result.new(status: :error, error: RailsAiBridge::Registry::ConnectionError.new("provider call failed (#{error.class}): #{sanitize_message(error.message)}"))
        ensure
          close_transport(transport)
        end
      end

      # Lightweight reachability probe: validates the endpoint, opens a
      # transport, lists tools, and closes. Does not call any tool.
      #
      # @param timeout [Numeric, nil] per-probe timeout in seconds; nil skips timeout
      # @return [Result]
      def probe(timeout: nil)
        endpoint = @provider.endpoint
        transport = nil
        begin
          policy_result = @policy.call(endpoint)
          return Result.new(status: :error, error: policy_result.error) unless policy_result.success?

          canonical_uri = policy_result.uri
          headers = resolve_auth(endpoint, canonical_uri)
          transport = @transport_factory.call(canonical_uri, policy_result.addresses, headers)
          if timeout
            Timeout.timeout(timeout) { transport.tools }
          else
            transport.tools
          end
          Result.new(status: :success, content: nil, provenance: provenance_for(canonical_uri), error: nil)
        rescue RailsAiBridge::Registry::ContextProviderError => error
          Result.new(status: :error, error: error)
        rescue Timeout::Error
          Result.new(status: :error, error: RailsAiBridge::Registry::TimeoutError.new('provider probe timed out'))
        rescue StandardError => error
          Result.new(status: :error, error: RailsAiBridge::Registry::ConnectionError.new("provider probe failed (#{error.class}): #{sanitize_message(error.message)}"))
        ensure
          close_transport(transport)
        end
      end

      private

      # @param endpoint [String] the raw provider endpoint
      # @param uri [URI] the canonical, credential-free provider URI
      # @return [Hash] auth headers for the transport call
      # @raise [AuthenticationError] when the auth resolver raises
      def resolve_auth(endpoint, uri)
        return {} unless @auth_resolver

        @auth_resolver.call(endpoint, uri)
      rescue StandardError => error
        raise AuthenticationError, "authentication resolution failed (#{error.class})"
      end

      # @param transport [Object, nil] the active transport
      # @return [void]
      def close_transport(transport)
        transport&.close
      rescue StandardError
        # Intentionally swallow close failures so the original result is preserved.
        nil
      end

      # @param tool_name [String]
      # @return [Boolean] whether the tool is declared in the provider manifest
      def tool_declared?(tool_name)
        @provider.tools.any? { |spec| spec.name == tool_name }
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

      # @param message [String] raw error message
      # @return [String] sanitized message with URLs and paths redacted
      def sanitize_message(message)
        RailsAiBridge::Registry::MessageSanitizer.sanitize(message)
      end
    end
  end
end
