# frozen_string_literal: true

module RailsAiBridge
  # Service-specific error hierarchy for consistent error handling.
  #
  # Provides a base error class and specific error types for different
  # failure scenarios in service operations. Inherits from existing
  # top-level error classes to maintain consistent error taxonomy.
  #
  # @example Raising a service error
  #   raise RailsAiBridge::ServiceErrors::ValidationError, "Invalid input data"
  #
  # @example Rescue pattern
  #   begin
  #     # service operation
  #   rescue RailsAiBridge::ServiceErrors::NotFoundError => e
  #     Service::Result.new(false, errors: [e.message])
  #   end
  module ServiceErrors
    # Base error class for all service-related exceptions.
    class BaseError < StandardError; end

    # Raised when validation fails for input data.
    class ValidationError < BaseError; end

    # Raised when a requested resource is not found.
    # Inherits from top-level NotFoundError for consistency.
    class NotFoundError < ::RailsAiBridge::NotFoundError; end

    # Raised when authorization fails.
    class AuthorizationError < BaseError; end

    # Raised when configuration is invalid.
    # Inherits from top-level ConfigurationError for consistency.
    class ConfigurationError < ::RailsAiBridge::ConfigurationError; end

    # Raised when introspection operations fail.
    # Inherits from top-level IntrospectionError for consistency.
    class IntrospectionError < ::RailsAiBridge::IntrospectionError; end

    # Raised when serialization operations fail.
    class SerializationError < BaseError; end
  end
end
