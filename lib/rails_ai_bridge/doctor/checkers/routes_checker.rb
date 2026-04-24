# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies +config/routes.rb+ exists.
      class RoutesChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ when routes file exists; +:fail+ otherwise
        def call
          routes_path = File.join(app.root, 'config/routes.rb')
          check(
            'Routes',
            File.exist?(routes_path),
            pass: { message: 'config/routes.rb found' },
            fail: { status: :fail, message: 'config/routes.rb not found',
                    fix: "Ensure you're in a Rails app root directory" }
          )
        end
      end
    end
  end
end
