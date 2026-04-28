# frozen_string_literal: true

require_relative 'reek_helper'
require 'bundler/setup'
require 'combustion'
# Resolve the dummy app under project ./spec/internal (gem default "/spec/internal" is an absolute path).
Combustion.path = 'spec/internal'

Combustion.initialize! :active_record, :action_controller do
  config.eager_load = false
end

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
  end
end

# Combustion schedules DB setup in a +to_prepare+ hook; RSpec examples can run before
# that fires, leaving :memory: SQLite empty. Load schema synchronously for deterministic specs.
Combustion::Database.setup

require 'rails_ai_bridge'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
