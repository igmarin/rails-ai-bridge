# frozen_string_literal: true

require 'delegate'
require 'digest'
require 'json'
require 'mcp'

module RailsAiBridge
  # Caches MCP tool call results keyed by a stable fingerprint of the arguments.
  #
  # The cache is in-memory, per-process, and TTL-based. It ignores +server_context+
  # when fingerprinting so identical client requests share the same cached response.
  #
  # Enable by setting +config.mcp.tool_result_cache_ttl+ to a positive number of seconds.
  class ToolResultCache
    @cache = {}
    @mutex = Mutex.new

    # Wraps a tool class so that calls are routed through the cache.
    class CachedTool < SimpleDelegator
      def initialize(tool_class)
        super
        @tool_class = tool_class
        @server_context_param = detect_server_context_param(tool_class.method(:call))
      end

      # @param server_context [Object, nil] passed by the MCP transport (ignored for cache keys)
      # @param arguments [Hash] tool arguments from the client
      # @return [MCP::Tool::Response]
      def call(server_context: nil, **arguments)
        ToolResultCache.fetch_response(@tool_class.tool_name, arguments) do
          invoke_tool(arguments, server_context)
        end
      end

      private

      def invoke_tool(arguments, server_context)
        case @server_context_param
        when :server_context
          @tool_class.call(**arguments, server_context: server_context)
        when :_server_context
          @tool_class.call(**arguments, _server_context: server_context)
        else
          @tool_class.call(**arguments)
        end
      end

      def detect_server_context_param(method_object)
        parameters = method_object.parameters
        keyish = %i[key keyreq].freeze
        return :server_context if parameters.any? { |type, name| name == :server_context && keyish.include?(type) }
        return :_server_context if parameters.any? { |type, name| name == :_server_context && keyish.include?(type) }
        return :server_context if parameters.any? { |type, _| type == :keyrest }

        nil
      end
    end

    class << self
      # Wraps a tool class if caching is enabled; otherwise returns the class unchanged.
      #
      # @param tool_class [Class] an +MCP::Tool+ subclass
      # @return [Class, CachedTool]
      def maybe_wrap(tool_class)
        enabled? ? wrap(tool_class) : tool_class
      end

      # Wraps a tool class so every call goes through the cache.
      #
      # @param tool_class [Class]
      # @return [CachedTool]
      def wrap(tool_class)
        CachedTool.new(tool_class)
      end

      # Fetches a cached response or yields to compute it.
      #
      # @param tool_name [String]
      # @param arguments [Hash]
      # @yieldreturn [MCP::Tool::Response]
      # @return [MCP::Tool::Response]
      def fetch_response(tool_name, arguments)
        return yield unless enabled?

        key = cache_key(tool_name, arguments)

        mutex.synchronize do
          entry = cache[key]
          return entry[:response] if entry && ttl_valid?(entry)
        end

        response = yield
        mutex.synchronize { cache[key] = { response: response, fetched_at: monotonic_now } }
        response
      end

      # Clears all cached tool results.
      #
      # @return [void]
      def reset!
        mutex.synchronize { @cache = {} }
      end

      # @return [Boolean] whether tool result caching is enabled
      def enabled?
        RailsAiBridge.configuration.mcp.tool_result_cache_ttl.to_i.positive?
      end

      private

      attr_reader :cache, :mutex

      def cache_key(tool_name, arguments)
        "#{tool_name}:#{argument_fingerprint(arguments)}"
      end

      def argument_fingerprint(arguments)
        normalized = arguments.transform_keys(&:to_s).sort.to_h
        Digest::SHA256.hexdigest(JSON.generate(normalized))
      end

      def ttl_valid?(entry)
        (monotonic_now - entry[:fetched_at]) < RailsAiBridge.configuration.mcp.tool_result_cache_ttl.to_i
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
