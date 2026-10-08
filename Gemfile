# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in rails-ai-bridge.gemspec
gemspec

group :development, :test do
  gem 'archspec', '~> 1.1.0'
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
  # simplecov 1.3+ requires Ruby >= 3.3; the gem still supports Ruby 3.2 (see gemspec).
  simplecov_version = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.3') ? '~> 1.3.2' : '~> 1.2.0'
  gem 'simplecov', simplecov_version
  gem 'skunk', '~> 0.5'
  gem 'sqlite3', '~> 2.9', '>= 2.9.6'
end

# Mutation testing requires Ruby >= 3.3.
# mutant-rspec is installed via the mutation workflow's Gemfile-mutation, not here,
# to avoid breaking bundle resolution on Ruby 3.2 CI matrix.

gem 'webrick', '~> 1.9', group: %i[development test]
gem 'yard', '~> 0.9', group: :development
