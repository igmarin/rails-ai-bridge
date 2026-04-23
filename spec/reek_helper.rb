# frozen_string_literal: true

# Reek code quality analysis configuration
# This helper ensures Reek is available during test execution
#
# - Locally: enabled on every `bundle exec rspec` unless REEK=false
# - CI: enabled always (reek is lightweight)
reek_enabled = ENV['REEK'] != 'false'

if reek_enabled
  begin
    require 'reek'
    # :nocov:
    warn '🔍 Reek code quality analysis available' if ENV['DEBUG']
    # :nocov:
  rescue LoadError
    # Reek not available, continue without it
  end
end
