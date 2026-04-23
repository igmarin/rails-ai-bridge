# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies a +spec+ or +test+ directory exists.
      class TestsChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ when a test tree exists; +:warn+ otherwise
        def call
          spec_dir = File.join(app.root, 'spec')
          test_dir = File.join(app.root, 'test')
          framework = Dir.exist?(spec_dir) ? 'RSpec' : 'Minitest'

          check(
            'Tests',
            Dir.exist?(spec_dir) || Dir.exist?(test_dir),
            pass: { message: "#{framework} test directory found" },
            fail: { status: :warn, message: 'No test directory found',
                    fix: 'Set up tests with `rails generate rspec:install` or use default Minitest' }
          )
        end
      end
    end
  end
end
