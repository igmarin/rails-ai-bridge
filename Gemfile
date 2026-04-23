# frozen_string_literal: true

source "https://rubygems.org"

gemspec

rails_version = ENV.fetch("RAILS_VERSION", "8.0")

# Using irb (built-in) instead of pry for better security

sqlite_version =
  if rails_version.start_with?("8")
    ">= 2.1"
  else
    "~> 1.7"
  end

group :development, :test do
  gem "railties", "~> #{rails_version}.0"
  # gem "skunk" # TODO: No MFA alternative available - temporarily removed
  gem "activerecord", "~> #{rails_version}.0"
  gem "sqlite3", sqlite_version
end
