# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Authentication with the provider failed or was rejected.
    class AuthenticationError < ContextProviderError
      # @param message [String] safe, credential-free message
      # @return [AuthenticationError]
      def initialize(message)
        super(message, category: :authentication)
      end
    end
  end
end
