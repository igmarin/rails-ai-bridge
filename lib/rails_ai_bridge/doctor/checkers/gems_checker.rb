# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies +Gemfile.lock+ is present for dependency introspection.
      class GemsChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ when lockfile exists; +:warn+ otherwise
        def call
          lock_path = File.join(app.root, 'Gemfile.lock')
          check(
            'Gems',
            File.exist?(lock_path),
            pass: { message: 'Gemfile.lock found' },
            fail: { status: :warn, message: 'Gemfile.lock not found', fix: 'Run `bundle install` to generate it' }
          )
        end
      end
    end
  end
end
