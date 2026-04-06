# frozen_string_literal: true

module RailsAiBridge
  # Service-specific error hierarchy for consistent error handling.
  #
  # Provides a base error class and specific error types for different
  # failure scenarios in service operations.
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
    class NotFoundError < BaseError; end
    
    # Raised when authorization fails.
    class AuthorizationError < BaseError; end
    
    # Raised when configuration is invalid.
    class ConfigurationError < BaseError; end
    
    # Raised when introspection operations fail.
    class IntrospectionError < BaseError; end
    
    # Raised when serialization operations fail.
    class SerializationError < BaseError; end
  end
end
