# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Scans Stimulus controllers and extracts targets, values, and actions.
    class StimulusIntrospector
      attr_reader :app

      # Initializes the Stimulus introspector and path resolver.
      #
      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
        @path_resolver = PathResolver.new(app)
      end

      def call
        controllers = @path_resolver.glob_for('app/javascript/controllers', '**/*_controller.{js,ts}').filter_map do |path|
          parse_controller(path)
        end

        { controllers: controllers }
      rescue StandardError => error
        { error: error.message }
      end

      private

      def parse_controller(path)
        relative = stimulus_relative_path(path)
        name = relative.sub(/_controller\.(js|ts)\z/, '').tr('/', '--')
        content = File.read(path)

        {
          name: name,
          file: relative,
          targets: extract_targets(content),
          values: extract_values(content),
          actions: extract_actions(content),
          outlets: extract_outlets(content),
          classes: extract_classes(content)
        }
      rescue StandardError => error
        { name: File.basename(path), error: error.message }
      end

      # Converts an absolute Stimulus controller path to the logical controller path.
      #
      # @param path [String] absolute source path
      # @return [String] path relative to the logical +app/javascript/controllers+ directory
      def stimulus_relative_path(path)
        @path_resolver.logical_file_path(path, logical_path: 'app/javascript/controllers')
                      .delete_prefix('app/javascript/controllers/')
      end

      def extract_targets(content)
        match = content.match(/static\s+targets\s*=\s*\[([^\]]*)\]/)
        return [] unless match

        match[1].scan(/["'](\w+)["']/).flatten
      end

      def extract_values(content)
        match = content.match(/static\s+values\s*=\s*\{([^}]*)\}/m)
        return {} unless match

        match[1].scan(/(\w+)\s*:\s*(\w+)/).to_h
      end

      def extract_actions(content)
        content.scan(/^\s+(?:async\s+)?(\w+)\s*\([^)]*\)\s*\{/).flatten
               .reject do |m|
          %w[constructor connect disconnect initialize if else for while switch catch
             function].include?(m)
        end
      end

      def extract_outlets(content)
        match = content.match(/static\s+outlets\s*=\s*\[([^\]]*)\]/)
        return [] unless match

        match[1].scan(/["']([^"']+)["']/).flatten
      end

      def extract_classes(content)
        match = content.match(/static\s+classes\s*=\s*\[([^\]]*)\]/)
        return [] unless match

        match[1].scan(/["']([^"']+)["']/).flatten
      end
    end
  end
end
