# frozen_string_literal: true

module RailsAiBridge
  module ServiceErrors
    class BaseError < StandardError; end
    class ValidationError < BaseError; end
    class NotFoundError < BaseError; end
    class AuthorizationError < BaseError; end
    class ConfigurationError < BaseError; end
    class IntrospectionError < BaseError; end
    class SerializationError < BaseError; end
  end
end
