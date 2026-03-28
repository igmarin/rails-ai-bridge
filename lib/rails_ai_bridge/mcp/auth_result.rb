# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    # Result of {HttpAuth} / strategy authentication (strategies do not raise for expected failures).
    AuthResult = Data.define(:success, :context, :error) do
      # @return [Boolean]
      def success? = success

      # @return [Boolean]
      def failure? = !success

      # @param context [Object, nil]
      # @return [AuthResult]
      def self.ok(context = nil)
        new(success: true, context: context, error: nil)
      end

      # @param error [Symbol, String, nil]
      # @return [AuthResult]
      def self.fail(error = :unauthorized)
        new(success: false, context: nil, error: error)
      end
    end
  end
end
