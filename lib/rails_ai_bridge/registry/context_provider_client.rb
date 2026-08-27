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
      # @param timeout_seconds [Numeric, nil] per-call timeout in seconds; nil disables the timeout
      # @param cleanup_deadline_seconds [Numeric, nil] maximum time to wait for transport.close; nil disables the deadline
      # @return [ContextProviderClient]
      def initialize(provider:, policy:, transport_factory:, auth_resolver:, timeout_seconds: nil, cleanup_deadline_seconds: 5.0)
        @provider = provider
        @policy = policy
        @transport_factory = transport_factory
        @auth_resolver = auth_resolver
        @timeout_seconds = timeout_seconds
        @cleanup_deadline_seconds = clamp_cleanup_deadline(cleanup_deadline_seconds, timeout_seconds)
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
          policy_result = with_timeout { @policy.call(endpoint) }
          return Result.new(status: :error, error: policy_result.error) unless policy_result.success?

          return Result.new(status: :error, error: RemoteToolError.new("tool #{tool_label} is not declared in the provider manifest")) unless tool_declared?(tool_name)

          canonical_uri = policy_result.uri
          headers = resolve_auth(endpoint, canonical_uri)
          transport = with_timeout { @transport_factory.call(canonical_uri, policy_result.addresses, headers) }
          remote_tool = with_timeout { find_tool(transport, tool_name) }
          return Result.new(status: :error, error: RemoteToolError.new("tool #{tool_label} is not allowed")) unless remote_tool

          content = with_timeout { transport.call_tool(name: tool_name, arguments: arguments) }
          Result.new(status: :success, content: sanitize_content(content), provenance: provenance_for(canonical_uri), error: nil)
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
        effective_timeout = timeout || @timeout_seconds
        begin
          policy_result = with_timeout(effective_timeout) { @policy.call(endpoint) }
          return Result.new(status: :error, error: policy_result.error) unless policy_result.success?

          canonical_uri = policy_result.uri
          headers = resolve_auth(endpoint, canonical_uri)
          transport = with_timeout(timeout) { @transport_factory.call(canonical_uri, policy_result.addresses, headers) }
          with_timeout(timeout) { transport.tools }
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

      # @param cleanup_deadline_seconds [Numeric, nil] requested cleanup deadline
      # @param timeout_seconds [Numeric, nil] per-call timeout
      # @return [Numeric, nil] cleanup deadline capped at the per-call timeout
      def clamp_cleanup_deadline(cleanup_deadline_seconds, timeout_seconds)
        return nil unless cleanup_deadline_seconds
        return cleanup_deadline_seconds unless timeout_seconds

        [cleanup_deadline_seconds, timeout_seconds].min
      end

      # @param timeout [Numeric, nil] the timeout to apply; defaults to the configured timeout
      # @param block [Proc] the operation to time-box
      # @return [Object] the block result
      # @raise [Timeout::Error] when the timeout expires
      def with_timeout(timeout = @timeout_seconds, &)
        return yield unless timeout

        Timeout.timeout(timeout, &)
      end

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
        return unless transport

        perform_close(transport)
      rescue StandardError => error
        # Intentionally swallow close failures so the original result is preserved.
        Rails.logger&.warn do
          if error.is_a?(Timeout::Error)
            'ContextProviderClient transport.close exceeded cleanup deadline'
          else
            "ContextProviderClient transport.close failed (#{error.class}): #{sanitize_message(error.message)}"
          end
        end
      end

      # @param transport [Object] the active transport
      # @return [void]
      def perform_close(transport)
        close = proc { transport.close }
        if @cleanup_deadline_seconds
          Timeout.timeout(@cleanup_deadline_seconds, &close)
        else
          close.call
        end
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

      # Recursively redact credential values in successful provider content
      # before it reaches the MCP response. Handles String, Hash (keys and
      # values), and Array.
      # @param content [String, Hash, Array, Object] raw provider content
      # @return [String, Hash, Array, Object] content with reflected auth values redacted from strings, hash keys, and values
      def sanitize_content(content)
        case content
        when String then sanitize_message(content)
        when Hash
          content.each_with_object({}) do |(key, value), sanitized|
            sanitized[sanitize_content(key)] = sanitize_content(value)
          end
        when Array then content.map { |value| sanitize_content(value) }
        else content
        end
      end
    end
  end
end
