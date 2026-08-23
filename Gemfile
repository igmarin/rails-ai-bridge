# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in rails-ai-bridge.gemspec
gemspec

group :development, :test do
  gem 'bundler-audit', '~> 0.9'
  gem 'combustion', '~> 1.3'
  gem 'rails', '~> 8.1'
  gem 'reek', '~> 6.1'
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.65'
  gem 'rubocop-performance', '~> 1.27'
  gem 'rubocop-rails', '~> 2.37'
  gem 'rubocop-rails-omakase', '~> 1.0'
  gem 'rubocop-rspec', '~> 3.10'
  gem 'simplecov', '~> 1.1.0'
  gem 'skunk', '~> 0.5'
  gem 'sqlite3', '~> 2.9'
end

# Mutation testing requires Ruby >= 3.3.
# mutant-rspec is installed via the mutation workflow's Gemfile-mutation, not here,
# to avoid breaking bundle resolution on Ruby 3.2 CI matrix.

gem 'yard', '~> 0.9', group: :development
