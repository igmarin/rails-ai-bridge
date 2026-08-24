# frozen_string_literal: true

require 'pathname'
require 'timeout'
require 'active_support/core_ext/string/inflections'

module RailsAiBridge
  # Manages bounded Rails app boot with stdout quarantine and timeout.
  #
  # In standalone mode, the executable needs to boot the host app's Rails
  # without contaminating stdout (which is used for MCP protocol) and without
  # hanging indefinitely. BootManager handles:
  #
  # 1. Locating the app root (Gemfile or config/application.rb)
  # 2. Quarantining boot stdout to stderr
  # 3. Honoring a configurable timeout
  # 4. Returning a structured result for StandardError and ScriptError failures
  # 5. Offering a StaticApp fallback for commands that permit it
  #
  # @example Bounded boot
  #   result = RailsAiBridge::BootManager.boot('/path/to/app', timeout: 30)
  #   if result[:success]
  #     app = result[:app]
  #   else
  #     app = RailsAiBridge::BootManager.static_fallback('/path/to/app')
  #   end
  #
  class BootManager
    # Commands that can operate in static mode (no Rails boot required).
    STATIC_ALLOWED_COMMANDS = %i[context inspect doctor].freeze

    # Default boot timeout in seconds.
    DEFAULT_TIMEOUT = 30

    class << self
      # Locates the Rails app root by searching for a Gemfile or
      # config/application.rb, walking up from the given path.
      #
      # @param start_path [String, Pathname] directory to search from
      # @return [Pathname, nil] the app root, or nil if not found
      # :reek:DuplicateMethodCall -- root_markers? is called in loop condition and result, both necessary
      def locate_root(start_path)
        current = Pathname.new(start_path).expand_path
        current = current.parent until current.root? || root_markers?(current)

        root_markers?(current) ? current : nil
      end

      # Attempts to boot the Rails app at the given root with a bounded timeout.
      #
      # Boot stdout is redirected to stderr so that MCP stdio protocol is not
      # contaminated. The result is always a structured hash — never raises.
      #
      # @param root [String, Pathname] the app root to boot
      # @param timeout [Integer] maximum seconds to wait for boot
      # @return [Hash] structured result:
      #   - +:success+ [Boolean] whether boot succeeded
      #   - +:app+ [Rails::Application, nil] the booted app (on success)
      #   - +:error+ [String, nil] error message (on failure)
      #   - +:error_class+ [String, nil] error class name (on failure)
      #   - +:stdout_quarantined+ [Boolean] whether stdout was redirected
      # :reek:TooManyStatements -- boot orchestration requires setup, rescue, and ensure
      def boot(root, timeout: DEFAULT_TIMEOUT)
        root = Pathname.new(root)
        original_stdout = $stdout
        $stdout = $stderr
        result = { stdout_quarantined: true, success: false, app: nil, error: nil, error_class: nil }

        begin
          Timeout.timeout(timeout) do
            require 'bundler/setup'
            require File.join(root, 'config', 'application')
            app_name = root.basename.to_s.classify
            app = app_name.constantize::Application
            app.initialize!
            result[:success] = true
            result[:app] = app
          end
        rescue StandardError, ScriptError => error
          prefix = error.is_a?(Timeout::Error) ? "Boot timed out after #{timeout}s: " : ''
          result[:error] = "#{prefix}#{error.message}"
          result[:error_class] = error.class.name
        ensure
          $stdout = original_stdout
        end

        result
      end

      # Returns a {StaticApp} for the given root, for use when boot fails or
      # is explicitly skipped via +--no-boot+.
      #
      # @param root [String, Pathname] the app root
      # @return [StaticApp]
      def static_fallback(root)
        StaticApp.new(root)
      end

      # Checks whether a command permits static fallback when boot fails.
      #
      # @param command [Symbol] the CLI command (e.g. +:context+, +:serve+)
      # @return [Boolean]
      def offer_static_fallback?(command)
        STATIC_ALLOWED_COMMANDS.include?(command)
      end
    end

    # @api private
    def self.root_markers?(path)
      path.join('Gemfile').exist? || path.join('config', 'application.rb').exist?
    end

    private_class_method :root_markers?
  end
end
