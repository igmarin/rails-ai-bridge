# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # Immutable result returned by every auth strategy.
    # Strategies never raise for expected failures — they return an +AuthResult+ instead.
    #
    # @example
    #   result = strategy.authenticate(request)
    #   render_unauthorized unless result.success?
    AuthResult = Data.define(:success, :context, :error) do
      # @return [Boolean] +true+ when authentication succeeded
      def success? = success

      # @return [Boolean] +true+ when authentication failed
      def failure? = !success

      # Builds a successful result, optionally carrying caller-provided context
      # (e.g. the decoded JWT payload or the resolved user object).
      #
      # @param context [Object, nil] arbitrary data from the strategy
      # @return [AuthResult]
      def self.ok(context = nil)
        new(success: true, context: context, error: nil)
      end

      # Builds a failure result.
      #
      # @param error [Symbol, String, nil] machine-readable reason
      #   (e.g. +:missing_token+, +:wrong_token+, +:decode_error+)
      # @return [AuthResult]
      def self.fail(error = :unauthorized)
        new(success: false, context: nil, error: error)
      end
    end
  end
end
