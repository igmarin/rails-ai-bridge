# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

rails_version = ENV.fetch('RAILS_VERSION', '8.0')

# Using irb (built-in) instead of pry for better security

sqlite_version =
  if rails_version.start_with?('8')
    '>= 2.1'
  else
    '~> 1.7'
  end

group :development, :test do
  gem 'railties', "~> #{rails_version}.0"
  # gem "skunk" # TODO: No MFA alternative available - temporarily removed
  gem 'activerecord', "~> #{rails_version}.0"
  gem 'sqlite3', sqlite_version

  # Development dependencies
  gem 'combustion', '~> 1.5' # Test Rails engines in isolation
  gem 'reek', '~> 6.0' # MFA enabled - code quality analysis
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.86'
  gem 'rubocop-rails', '~> 2.0' # MFA enabled - Rails-specific cops
  gem 'rubocop-rspec', '~> 3.0' # MFA enabled - RSpec-specific cops
  gem 'rubycritic', '~> 5.0' # MFA enabled - additional code metrics
  gem 'yard', '~> 0.9' # MFA enabled - documentation generation
end
