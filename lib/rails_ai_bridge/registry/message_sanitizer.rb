# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Redacts URLs, SSH URIs, file paths, and credential fields from error
    # messages before they are included in provider error results. Prevents
    # raw transport errors from leaking endpoints, query strings, file paths,
    # or credential values (tokens, passwords, API keys) into Doctor output.
    module MessageSanitizer
      # Credential field names commonly found in JSON or header-style error
      # responses. Matches are case-insensitive and redact the associated value.
      CREDENTIAL_PATTERNS = [
        /(?i:"(access_token|token|password|secret|api_key|apikey|authorization|auth_token|bearer)"\s*[:=]\s*"?[^",\s}]+)/,
        /(?i:(access_token|token|password|secret|api_key|apikey|authorization|auth_token|bearer)\s*[:=]\s*"?[^\s,}]+)/
      ].freeze

      # @param message [String] raw error message
      # @return [String] sanitized message with URLs, paths, and credentials redacted
      def self.sanitize(message)
        message.to_s
               .gsub(%r{[a-z][a-z0-9+.-]+://[^\s]+}i, '[redacted]')
               .gsub(/git@[^\s]+/, '[redacted]')
               .gsub(%r{(?<=\s|^|\(|'|"|`)/[A-Za-z0-9_.-]+(?:/[^\s]*)?}, '[redacted]')
               .gsub(/[A-Za-z]:\\[^\s]+/, '[redacted]')
               .gsub(/(?i:bearer\s+[^\s]+)/, '[redacted]')
               .gsub(/(?i:"(access_token|token|password|secret|api_key|apikey|authorization|auth_token)"\s*[:=]\s*"?[^",\s}]+)/, '[redacted]')
               .gsub(/(?i:(access_token|token|password|secret|api_key|apikey|authorization|auth_token)\s*[:=]\s*"?[^\s,}]+)/, '[redacted]')
      end
    end
  end
end
