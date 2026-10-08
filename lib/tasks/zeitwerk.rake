# frozen_string_literal: true

namespace :rails_ai_bridge do
  desc 'Eager-load all gem constants to verify Zeitwerk autoloading'
  task :check_zeitwerk do
    # This task lives in lib/tasks; the gem's lib directory is one directory up.
    # realpath guards against symlinked gem installs (e.g. Bundler paths on macOS).
    lib_dir = File.realpath(File.expand_path('..', __dir__))

    # Engine loading needs ActionDispatch::Routing::RouteSet and the
    # Rails::Engine base class. Both come from existing gem dependencies.
    require 'action_dispatch'
    require 'rails/engine'

    require 'rails_ai_bridge'

    # Only eager-load this gem's loader, not any host app loaders.
    loader = nil
    Zeitwerk::Registry.loaders.each do |l|
      next unless l.dirs.any? do |dir|
        File.exist?(dir) && File.realpath(dir) == lib_dir
      end

      loader = l
      break
    end
    raise 'RailsAiBridge Zeitwerk loader not found' if loader.nil?

    loader.eager_load
    puts 'Zeitwerk check passed'
  end
end
