# frozen_string_literal: true

require 'delegate'

module RailsAiBridge
  # Thin wrapper around ActiveSupport::Notifications for rails-ai-bridge events.
  #
  # Events are namespaced under +rails_ai_bridge+. If ActiveSupport::Notifications
  # is not available, the helper yields without instrumentation so the code can be
  # used outside of Rails without a hard dependency.
  module Instrumentation
    NAMESPACE = 'rails_ai_bridge'

    # Emits an instrumentation event.
    #
    # @param event [String] event name suffix (e.g. +tool.call+)
    # @param payload [Hash] extra payload attached to the event
    # @yield optional block to wrap; the block result is returned
    # @return [Object] the block result, or nil when no block is given
    def self.instrument(event, payload = {})
      return yield unless defined?(ActiveSupport::Notifications) && ActiveSupport::Notifications

      ActiveSupport::Notifications.instrument("#{NAMESPACE}.#{event}", payload) do
        yield if block_given?
      end
    end

    # Wraps an MCP tool class so every call emits a +rails_ai_bridge.tool.call+
    # event. Caching, when enabled, is handled by the inner wrapper so cache
    # hit/miss events stay separate from the invocation event.
    class InstrumentedTool < SimpleDelegator
      def initialize(tool_class)
        super
        @tool_class = tool_class
      end

      # @param server_context [Object, nil]
      # @param arguments [Hash]
      # @return [MCP::Tool::Response]
      def call(server_context: nil, **arguments)
        Instrumentation.instrument('tool.call', tool_name: @tool_class.tool_name, arguments: arguments) do
          @tool_class.call(server_context: server_context, **arguments)
        end
      end
    end
  end
end
