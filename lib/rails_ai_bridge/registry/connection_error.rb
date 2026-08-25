# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # The provider exchange failed due to a transport or network problem.
    class ConnectionError < ContextProviderError
      # @param message [String] safe, credential-free message
      # @return [ConnectionError]
      def initialize(message)
        super(message, category: :connection)
      end
    end
  end
end
