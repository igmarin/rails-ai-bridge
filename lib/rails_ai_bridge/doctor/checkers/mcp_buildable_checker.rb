# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class McpBuildableChecker < BaseChecker
        def call
          Server.new(app).build
          new_check(name: "MCP server", status: :pass, message: "MCP server builds successfully", fix: nil)
        rescue => e
          new_check(name: "MCP server", status: :fail, message: "MCP server failed to build: #{e.message}", fix: "Check mcp gem installation: `bundle info mcp`")
        end
      end
    end
  end
end
