# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Stable base class for outbound context-provider failures.
    # Subclasses expose a safe category and message; they never carry
    # raw SDK, Faraday, response-body, or credential details.
    class ContextProviderError < RailsAiBridge::Error
      # @return [Symbol] stable error category for callers and logs
      attr_reader :category

      # @return [String, nil] provider name associated with this error
      attr_accessor :provider_name

      # @param message [String] safe, credential-free message
      # @param category [Symbol] stable error category
      # @param provider_name [String, nil] provider name associated with this error
      # @return [ContextProviderError]
      def initialize(message, category: :unknown, provider_name: nil)
        super(message)
        @category = category
        @provider_name = provider_name
      end
    end
  end
end
