# frozen_string_literal: true

require "mcp"

module RailsAiBridge
  module Tools
    # Base class for all MCP tools exposed by rails-ai-bridge.
    # Inherits from the official MCP::Tool to get schema validation,
    # annotations, and protocol compliance for free.
    class BaseTool < MCP::Tool
      class << self
        # Convenience: access the Rails app and cached introspection
        def rails_app
          Rails.application
        end

        def config
          RailsAiBridge.configuration
        end

        # Cache introspection results with TTL + fingerprint invalidation
        def cached_context
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ttl = RailsAiBridge.configuration.cache_ttl

          if @cached_context && (now - @cache_timestamp) < ttl && !Fingerprinter.changed?(rails_app, @cache_fingerprint)
            return @cached_context
          end

          @cached_context = RailsAiBridge.introspect
          @cache_timestamp = now
          @cache_fingerprint = Fingerprinter.compute(rails_app)
          @cached_context
        end

        def reset_cache!
          @cached_context = nil
          @cache_timestamp = nil
          @cache_fingerprint = nil
        end

        # Helper: wrap text in an MCP::Tool::Response with safety-net truncation
        def text_response(text)
          max = RailsAiBridge.configuration.max_tool_response_chars
          if max && text.length > max
            truncated = text[0...max]
            truncated += "\n\n---\n_Response truncated (#{text.length} chars). Use `detail:\"summary\"` for an overview, or filter by a specific item (e.g. `table:\"users\"`)._"
            MCP::Tool::Response.new([ { type: "text", text: truncated } ])
          else
            MCP::Tool::Response.new([ { type: "text", text: text } ])
          end
        end
      end
    end
  end
end
