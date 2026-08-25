# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Stable base class for outbound context-provider failures.
    # Subclasses expose a safe category and message; they never carry
    # raw SDK, Faraday, response-body, or credential details.
    class ContextProviderError < RailsAiBridge::Error
      # @return [Symbol] stable error category for callers and logs
      attr_reader :category

      # @param message [String] safe, credential-free message
      # @param category [Symbol] stable error category
      # @return [ContextProviderError]
      def initialize(message, category: :unknown)
        super(message)
        @category = category
      end
    end
  end
end
