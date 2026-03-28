# frozen_string_literal: true

module RailsAiBridge
  module Mcp
    module Auth
      # Shared helpers for Bearer-based strategies.
      class BaseStrategy
        # @param request [Rack::Request]
        # @return [String, nil] raw token without "Bearer " prefix
        def extract_bearer(request)
          auth = request.get_header("HTTP_AUTHORIZATION")
          return nil if auth.blank?

          match = auth.match(/\ABearer\s+(.+)\z/i)
          match ? match[1].to_s.strip : nil
        end
      end
    end
  end
end
