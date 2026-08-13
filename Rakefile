# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

Dir.glob('lib/tasks/*.rake').each { |task| load task }

task default: :spec
