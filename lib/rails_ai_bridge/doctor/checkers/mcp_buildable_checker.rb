# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies the MCP server can be built for this application.
      class McpBuildableChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ on successful build; +:fail+ if build raises
        def call
          Server.new(app).build
          new_check(name: 'MCP server', status: :pass, message: 'MCP server builds successfully', fix: nil)
        rescue StandardError => e
          new_check(name: 'MCP server', status: :fail, message: "MCP server failed to build: #{e.message}",
                    fix: 'Check mcp gem installation: `bundle info mcp`')
        end
      end
    end
  end
end
