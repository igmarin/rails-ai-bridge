# frozen_string_literal: true

namespace :perf do
  desc 'Generate perf baseline JSON (spec/support/perf_baseline.json)'
  task :generate_baseline do
    require 'combustion'
    Combustion.path = 'spec/internal'
    Combustion.initialize! :active_record, :action_controller do
      config.eager_load = false
    end
    Combustion::Database.setup
    require_relative '../../spec/support/perf_baseline'
    PerfBaseline.generate
  end

  desc 'Run perf benchmarks and compare against baseline (fails on >20% regression)'
  task :compare do
    require 'combustion'
    Combustion.path = 'spec/internal'
    Combustion.initialize! :active_record, :action_controller do
      config.eager_load = false
    end
    Combustion::Database.setup
    require_relative '../../spec/support/perf_baseline'
    PerfBaseline.run
  end
end
