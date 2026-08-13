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
  gem 'rubocop-rails', '~> 2.35'
  gem 'rubocop-rails-omakase', '~> 1.0'
  gem 'rubocop-rspec', '~> 3.10'
  gem 'simplecov', '~> 1.0.0'
  gem 'skunk', '~> 0.5'
  gem 'sqlite3', '~> 2.9'
end

# Mutation testing requires Ruby >= 3.3; install with `bundle install --with mutation`
group :mutation do
  gem 'mutant-rspec', '~> 0.16', require: false
end
