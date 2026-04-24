# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    module Auth
      # Shared helpers for Bearer-token–based auth strategies.
      #
      # @abstract Subclasses must implement +#authenticate(request) -> AuthResult+.
      class BaseStrategy
        # Extracts the raw Bearer credential from an +Authorization+ header.
        #
        # @param request [Rack::Request]
        # @return [String, nil] token without the +"Bearer "+ prefix, or +nil+ when absent/malformed
        def extract_bearer(request)
          auth = request.get_header('HTTP_AUTHORIZATION')
          return nil if auth.blank?

          match = auth.match(/\ABearer\s+(.+)\z/i)
          match ? match[1].to_s.strip : nil
        end
      end
    end
  end
end
