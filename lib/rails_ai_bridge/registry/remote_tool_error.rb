# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # The requested tool is unknown, not advertised as safe, or not allowed.
    class RemoteToolError < ContextProviderError
      # @param message [String] safe, credential-free message
      # @return [RemoteToolError]
      def initialize(message)
        super(message, category: :remote_tool)
      end
    end
  end
end
