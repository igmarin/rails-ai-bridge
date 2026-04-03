# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Ensures +rails_get_view+ is registered when views and +:views+ introspection matter.
      class ViewMcpToolChecker < BaseChecker
        # @return [Doctor::Check] +:pass+, +:warn+, or +:fail+ depending on views and tool registration
        def call
          return new_check(name: "View MCP tool", status: :pass, message: "No view files detected; view MCP tool not required", fix: nil) unless view_files_present?

          unless RailsAiBridge.configuration.introspectors.include?(:views)
            return new_check(
              name: "View MCP tool",
              status: :warn,
              message: "Views detected but :views introspector is disabled",
              fix: "Enable it with `RailsAiBridge.configure { |c| c.introspectors |= [:views] }`"
            )
          end

          check(
            "View MCP tool",
            tool_registered?("rails_get_view"),
            pass: { message: "rails_get_view available for view inspection" },
            fail: { status: :fail, message: "rails_get_view is not registered", fix: "Register `RailsAiBridge::Tools::GetView` in the MCP server" }
          )
        end

        private

        def tool_registered?(tool_name)
          (RailsAiBridge::Server::TOOLS + RailsAiBridge.configuration.additional_tools).any? { |tool| tool.tool_name == tool_name }
        end

        def view_files_present?
          dir = File.join(app.root, "app/views")
          Dir.exist?(dir) && Dir.glob(File.join(dir, "**/*")).reject { |path| File.directory?(path) }.any?
        end
      end
    end
  end
end
