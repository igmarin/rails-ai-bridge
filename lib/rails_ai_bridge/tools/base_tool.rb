# frozen_string_literal: true

require 'mcp'

module RailsAiBridge
  module Tools
    # Base class for all MCP tools exposed by rails-ai-bridge.
    # Inherits from the official MCP::Tool to get schema validation,
    # annotations, and protocol compliance for free.
    class BaseTool < MCP::Tool
      class << self
        # @return [Rails::Application] the host Rails application
        def rails_app
          Rails.application
        end

        # @return [RailsAiBridge::Configuration] gem configuration
        def config
          RailsAiBridge.configuration
        end

        # Full introspection hash (TTL + fingerprint invalidation).
        #
        # @return [Hash] context payload keyed by introspector symbol
        def cached_context
          ContextProvider.fetch(rails_app)
        end

        # Returns a single introspection section via the shared context provider.
        #
        # @param section [Symbol] introspector key
        # @return [Object, nil] section payload
        def cached_section(section)
          ContextProvider.fetch_section(section, rails_app)
        end

        # Clears the shared introspection cache used by MCP tools.
        #
        # @return [void]
        def reset_cache!
          ContextProvider.reset!
        end

        # Wraps markdown (or plain text) in a +MCP::Tool::Response+, truncating when
        # +max_tool_response_chars+ is set on the gem configuration.
        #
        # @param text [String] tool body to return to the client
        # @return [MCP::Tool::Response]
        def text_response(text)
          max = RailsAiBridge.configuration.max_tool_response_chars
          if max && text.length > max
            suffix = "\n\n---\n_Response truncated (#{text.length} chars). Use `detail:\"summary\"` for an overview, or filter by a specific item (e.g. `table:\"users\"`)._"
            available_chars = max - suffix.length
            truncated = if available_chars.positive?
                          "#{text[0...available_chars]}#{suffix}"
                        else
                          suffix[0...max]
                        end
            MCP::Tool::Response.new([{ type: 'text', text: truncated }])
          else
            MCP::Tool::Response.new([{ type: 'text', text: text }])
          end
        end
      end
    end
  end
end
