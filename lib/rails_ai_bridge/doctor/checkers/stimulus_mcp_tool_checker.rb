# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Ensures +rails_get_stimulus+ is registered when Stimulus files and introspection matter.
      class StimulusMcpToolChecker < BaseChecker
        # @return [Doctor::Check] +:pass+, +:warn+, or +:fail+ depending on Stimulus files and tool registration
        def call
          unless stimulus_files_present?
            return new_check(name: 'Stimulus MCP tool', status: :pass,
                             message: 'No Stimulus controllers detected; stimulus MCP tool not required', fix: nil)
          end

          unless RailsAiBridge.configuration.introspectors.include?(:stimulus)
            return new_check(
              name: 'Stimulus MCP tool',
              status: :warn,
              message: 'Stimulus controllers detected but :stimulus introspector is disabled',
              fix: 'Enable it with `RailsAiBridge.configure { |c| c.introspectors |= [:stimulus] }`'
            )
          end

          check(
            'Stimulus MCP tool',
            tool_registered?('rails_get_stimulus'),
            pass: { message: 'rails_get_stimulus available for Hotwire UI inspection' },
            fail: { status: :fail, message: 'rails_get_stimulus is not registered', fix: 'Register `RailsAiBridge::Tools::GetStimulus` in the MCP server' }
          )
        end

        private

        def tool_registered?(tool_name)
          (RailsAiBridge::Server::TOOLS + RailsAiBridge.configuration.additional_tools).any? { |tool| tool.tool_name == tool_name }
        end

        def stimulus_files_present?
          dir = File.join(app.root, 'app/javascript/controllers')
          Dir.exist?(dir) && Dir.glob(File.join(dir, '**/*_controller.{js,ts}')).any?
        end
      end
    end
  end
end
