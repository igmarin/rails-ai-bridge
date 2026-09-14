# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Warns when HTTP MCP is auto-mounted but {Config::Mcp#http_log_json} is still off.
      class HttpStructuredLogChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ when auto-mount is off or logs are on; +:warn+ otherwise
        def call
          unless RailsAiBridge.configuration.auto_mount
            return new_check(
              name: 'HTTP structured logs',
              status: :pass,
              message: 'HTTP MCP auto-mount is off; structured HTTP logs not required',
              fix: nil
            )
          end

          check(
            'HTTP structured logs',
            RailsAiBridge.configuration.mcp.http_log_json,
            pass: { message: 'HTTP MCP structured logs are enabled (http_log_json)' },
            fail: {
              status: :warn,
              message: 'HTTP MCP is auto-mounted but structured JSON request logs are off',
              fix: 'Set `config.mcp.http_log_json = true` to emit one JSON line per MCP HTTP request'
            }
          )
        end
      end
    end
  end
end
