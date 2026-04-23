# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Scans view layer: layouts, templates, partials, helpers,
    # view components, and template engine detection.
    class ViewIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call
        {
          layouts: extract_layouts,
          templates: extract_templates,
          partials: extract_partials,
          helpers: extract_helpers,
          view_components: extract_view_components,
          template_engines: detect_template_engines
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def root
        app.root.to_s
      end

      def views_dir
        File.join(root, 'app/views')
      end

      def extract_layouts
        dir = File.join(views_dir, 'layouts')
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, '*')).filter_map do |path|
          File.basename(path) if File.file?(path)
        end.sort
      end

      def extract_templates
        return {} unless Dir.exist?(views_dir)

        templates = {}
        Dir.glob(File.join(views_dir, '**/*')).each do |path|
          next if File.directory?(path)

          relative = path.sub("#{views_dir}/", '')
          next if relative.start_with?('layouts/')
          next if File.basename(relative).start_with?('_')

          controller = File.dirname(relative)
          templates[controller] ||= []
          templates[controller] << File.basename(relative)
        end

        templates.transform_values(&:sort)
      end

      def extract_partials
        return { shared: [], per_controller: {} } unless Dir.exist?(views_dir)

        shared = []
        per_controller = {}

        Dir.glob(File.join(views_dir, '**/_*')).each do |path|
          relative = path.sub("#{views_dir}/", '')
          dir = File.dirname(relative)
          name = File.basename(relative)

          if %w[shared application].include?(dir)
            shared << name
          else
            per_controller[dir] ||= []
            per_controller[dir] << name
          end
        end

        { shared: shared.sort, per_controller: per_controller.transform_values(&:sort) }
      end

      def extract_helpers
        dir = File.join(root, 'app/helpers')
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, '**/*.rb')).filter_map do |path|
          relative = path.sub("#{dir}/", '')
          content = File.read(path)
          methods = content.scan(/^\s*def\s+(\w+)/).flatten
          {
            file: relative,
            methods: methods
          }
        rescue StandardError
          nil
        end.sort_by { |h| h[:file] }
      end

      def extract_view_components
        dir = File.join(root, 'app/components')
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, '**/*.rb')).filter_map do |path|
          path.sub("#{dir}/", '').sub(/\.rb\z/, '')
        end.sort
      end

      def detect_template_engines
        return [] unless Dir.exist?(views_dir)

        extensions = Dir.glob(File.join(views_dir, '**/*')).filter_map do |path|
          next if File.directory?(path)

          ext = File.extname(path).delete('.')
          ext unless ext.empty?
        end

        engines = []
        engines << 'erb' if extensions.include?('erb')
        engines << 'haml' if extensions.include?('haml')
        engines << 'slim' if extensions.include?('slim')
        engines << 'jbuilder' if extensions.include?('jbuilder')
        engines
      end
    end
  end
end
