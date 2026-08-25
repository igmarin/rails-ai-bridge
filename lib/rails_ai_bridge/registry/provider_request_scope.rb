# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Per-invocation memo for context-provider tool results.
    #
    # The scope lives for one MCP tool invocation (one `rails_get_provider_context`
    # call). It is not a process-wide cache, Rails controller request cache, or
    # cross-request HTTP cache. The tool that creates the scope is responsible
    # for discarding it after the call completes.
    class ProviderRequestScope
      def initialize
        @cache = {}
      end

      # Returns the cached result for the given provider and tool, or yields
      # the block and stores the result for subsequent lookups.
      #
      # @param provider_name [String] provider identity
      # @param tool_name [String] remote tool name
      # @return [Object] the cached or freshly fetched result
      def fetch_or_store(provider_name, tool_name)
        key = [provider_name, tool_name]
        return @cache[key] if @cache.key?(key)

        @cache[key] = yield
      end

      # Removes all cached entries.
      #
      # @return [Hash] the cleared cache
      delegate :clear, to: :@cache
    end
  end
end
