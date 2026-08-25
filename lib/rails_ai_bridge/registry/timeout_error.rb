# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # The provider call exceeded its configured time budget.
    class TimeoutError < ContextProviderError
      # @param message [String] safe, credential-free message
      # @return [TimeoutError]
      def initialize(message)
        super(message, category: :timeout)
      end
    end
  end
end
