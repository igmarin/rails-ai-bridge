# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # The endpoint did not satisfy the configured policy.
    class PolicyError < ContextProviderError
      # @param message [String] safe, credential-free message
      # @return [PolicyError]
      def initialize(message)
        super(message, category: :policy)
      end
    end
  end
end
