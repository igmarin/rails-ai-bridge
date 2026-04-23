# frozen_string_literal: true

# SimpleCov must load before Combustion, Rails, or the gem under test.
#
# - Locally: enabled on every `bundle exec rspec` (CI env is unset).
# - GitHub Actions: enabled only when +COVERAGE=true+ (one matrix cell) to avoid redundant work.
coverage_enabled = ENV['COVERAGE'] == 'true' || ENV['CI'] != 'true'

if coverage_enabled
  require 'simplecov'

  SimpleCov.start do
    root File.expand_path('..', __dir__)

    track_files 'lib/**/*.rb'

    add_filter '/spec/'
    add_filter '/vendor/bundle/'
    add_filter '/lib/generators/rails_ai_bridge/install/templates/'

    add_group 'Core', 'lib/rails_ai_bridge'
    add_group 'Introspectors', 'lib/rails_ai_bridge/introspectors'
    add_group 'Tools', 'lib/rails_ai_bridge/tools'
    add_group 'Serializers', 'lib/rails_ai_bridge/serializers'
    add_group 'Generators', 'lib/generators'

    minimum_coverage line: 80
  end
end
