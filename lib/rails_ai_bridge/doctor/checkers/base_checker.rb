# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    # Pluggable checks invoked by {Doctor#run}; each returns a {Doctor::Check}.
    module Checkers
      # Shared helpers for filesystem and configuration checks against a Rails app.
      class BaseChecker
        attr_reader :app

        # @param app [Rails::Application] host application under inspection
        # @return [void]
        def initialize(app)
          @app = app
        end

        # @raise [NotImplementedError] unless overridden in a concrete checker
        # @return [Doctor::Check]
        def call
          raise NotImplementedError, "subclasses must implement #call"
        end

        private

        # Builds a {Doctor::Check} from a boolean condition and pass/fail option hashes.
        #
        # @param name [String] check display name
        # @param condition [Boolean] truthy uses +pass+ branch, falsy uses +fail+
        # @option pass [Symbol] :status (defaults to +:pass+ when merged)
        # @option pass [String] :message
        # @option pass [String, nil] :fix
        # @option fail [Symbol] :status (+:warn+ or +:fail+ typically)
        # @option fail [String] :message
        # @option fail [String, nil] :fix
        # @return [Doctor::Check]
        def check(name, condition, pass:, fail:)
          options = condition ? pass : fail
          default_pass_options = { status: :pass, fix: nil }
          final_options = { name: name }.merge(default_pass_options).merge(options)

          new_check(**final_options)
        end

        # @param name [String]
        # @param status [Symbol]
        # @param message [String]
        # @param fix [String, nil]
        # @return [Doctor::Check]
        def new_check(name:, status:, message:, fix:)
          RailsAiBridge::Doctor::Check.new(name: name, status: status, message: message, fix: fix)
        end
      end
    end
  end
end
