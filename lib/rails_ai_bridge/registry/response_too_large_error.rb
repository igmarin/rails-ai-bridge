# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # The provider response exceeded the configured size budget.
    class ResponseTooLargeError < ContextProviderError
      # @param message [String] safe, credential-free message
      # @return [ResponseTooLargeError]
      def initialize(message)
        super(message, category: :response_too_large)
      end
    end
  end
end
