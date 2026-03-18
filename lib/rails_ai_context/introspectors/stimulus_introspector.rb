# frozen_string_literal: true

module RailsAiContext
  module Introspectors
    # Scans Stimulus controllers and extracts targets, values, and actions.
    class StimulusIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call
        root = app.root.to_s
        controllers_dir = File.join(root, "app/javascript/controllers")
        return { controllers: [] } unless Dir.exist?(controllers_dir)

        controllers = Dir.glob(File.join(controllers_dir, "**/*_controller.{js,ts}")).sort.filter_map do |path|
          parse_controller(path, controllers_dir)
        end

        { controllers: controllers }
      rescue => e
        { error: e.message }
      end

      private

      def parse_controller(path, base_dir)
        relative = path.sub("#{base_dir}/", "")
        name = relative.sub(/_controller\.(js|ts)\z/, "").tr("/", "--")
        content = File.read(path)

        {
          name: name,
          file: relative,
          targets: extract_targets(content),
          values: extract_values(content),
          actions: extract_actions(content)
        }
      rescue => e
        { name: File.basename(path), error: e.message }
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
        content.scan(/^\s*(\w+)\s*\(/).flatten
               .reject { |m| %w[constructor connect disconnect initialize].include?(m) }
      end
    end
  end
end
