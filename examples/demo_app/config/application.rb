# frozen_string_literal: true

require_relative 'boot'

require 'rails'
# Pick the frameworks the demo needs. No database is required to boot or to
# generate context files — the gem parses db/schema.rb as text when no
# database connection is available.
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'

Bundler.require(*Rails.groups)

module DemoApp
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
  end
end
