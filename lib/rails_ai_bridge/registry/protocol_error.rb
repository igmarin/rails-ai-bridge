# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # The provider returned an unexpected or invalid MCP response.
    class ProtocolError < ContextProviderError
      # @param message [String] safe, credential-free message
      # @return [ProtocolError]
      def initialize(message)
        super(message, category: :protocol)
      end
    end
  end
end
