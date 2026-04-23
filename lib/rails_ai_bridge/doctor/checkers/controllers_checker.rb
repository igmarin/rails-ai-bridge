# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies +app/controllers+ contains controller Ruby files.
      class ControllersChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ when controller files exist; +:warn+ otherwise
        def call
          controllers_path = File.join(app.root, 'app/controllers', '**/*.rb')
          controllers = Dir.glob(controllers_path)

          check(
            'Controllers',
            controllers.any?,
            pass: { message: "#{controllers.size} controller files found" },
            fail: { status: :warn, message: 'No controller files found in app/controllers/',
                    fix: 'Generate controllers with `rails generate controller`' }
          )
        end
      end
    end
  end
end
