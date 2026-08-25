# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Redacts URLs, SSH URIs, and file paths from error messages before
    # they are included in provider error results. Prevents raw transport
    # errors from leaking endpoints, query strings, or file paths.
    module MessageSanitizer
      # @param message [String] raw error message
      # @return [String] sanitized message with URLs and paths replaced
      def self.sanitize(message)
        message.to_s
               .gsub(%r{https?://[^\s]+}i, '[redacted]')
               .gsub(%r{(ssh|git|file|ftp|sftp|ws|wss)://[^\s]+}i, '[redacted]')
               .gsub(/git@[^\s]+/, '[redacted]')
               .gsub(%r{(?:\A|\s)/[A-Za-z0-9_.-]+(?:/[^\s]*)?}, '[redacted]')
               .gsub(/[A-Za-z]:\\[^\s]+/, '[redacted]')
      end
    end
  end
end
