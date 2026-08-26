# frozen_string_literal: true

namespace :zeitwerk do
  desc 'Eager-load all gem constants to verify Zeitwerk autoloading'
  task :check do
    # This task lives in lib/tasks; the gem's lib directory is one directory up.
    lib_dir = File.expand_path('..', __dir__)

    # Engine loading needs ActionDispatch::Routing::RouteSet and the
    # Rails::Engine base class. Both come from existing gem dependencies.
    require 'action_dispatch'
    require 'rails/engine'

    require 'rails_ai_bridge'

    # Only eager-load this gem's loader, not any host app loaders.
    loader = nil
    Zeitwerk::Registry.loaders.each do |l|
      next unless l.dirs.include?(lib_dir)

      loader = l
      break
    end
    raise 'RailsAiBridge Zeitwerk loader not found' if loader.nil?

    loader.eager_load
    puts 'Zeitwerk check passed'
  end
end
