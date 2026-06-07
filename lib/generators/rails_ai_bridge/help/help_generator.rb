# frozen_string_literal: true

require_relative '../install/command_help'

module RailsAiBridge
  module Generators
    # Prints the full rails-ai-bridge command reference to the terminal.
    #
    # Useful for existing installs where the installer was already run and
    # users want to rediscover available commands without re-running install.
    #
    # @example
    #   rails g rails_ai_bridge:help
    class HelpGenerator < Rails::Generators::Base
      include CommandHelp

      desc 'Print the rails-ai-bridge command reference (bridge, MCP, skill registry).'

      def show_commands
        say ''
        say '=' * 50, :cyan
        say ' rails-ai-bridge — command reference', :cyan
        say '=' * 50, :cyan
        say ''
        print_command_reference
        say ''
        say 'Tip: run `rails g rails_ai_bridge:install` to (re)generate .mcp.json and config files.', :green
        say ''
      end
    end
  end
end
