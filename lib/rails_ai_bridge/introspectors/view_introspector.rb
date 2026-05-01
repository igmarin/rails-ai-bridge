# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Scans view layer: layouts, templates, partials, helpers,
    # view components, and template engine detection.
    class ViewIntrospector
      attr_reader :app

      # Accumulates renderable templates grouped by controller directory.
      class TemplateIndex
        # Initializes an empty template index.
        #
        # @return [void]
        def initialize
          @templates = {}
        end

        # Adds one relative view path when it represents a renderable template.
        #
        # @param relative [String] path relative to the logical +app/views+ directory
        # @return [void]
        def add(relative)
          basename = File.basename(relative)
          return if relative.start_with?('layouts/')
          return if basename.start_with?('_')

          @templates.fetch(File.dirname(relative)) do |controller|
            @templates[controller] = []
          end << basename
        end

        # Returns sorted templates grouped by controller directory.
        #
        # @return [Hash{String=>Array<String>}] template filenames keyed by controller path
        def to_h
          @templates.transform_values(&:sort)
        end
      end
      private_constant :TemplateIndex

      # Accumulates shared and controller-specific partial templates.
      class PartialIndex
        # Initializes empty shared and per-controller partial collections.
        #
        # @return [void]
        def initialize
          @shared = []
          @per_controller = {}
        end

        # Adds one relative view path when it represents a partial.
        #
        # @param relative [String] path relative to the logical +app/views+ directory
        # @return [void]
        def add(relative)
          dir = File.dirname(relative)
          name = File.basename(relative)

          if %w[shared application].include?(dir)
            @shared << name
          else
            @per_controller.fetch(dir) { |key| @per_controller[key] = [] } << name
          end
        end

        # Returns sorted shared and per-controller partial lists.
        #
        # @return [Hash] partial metadata with +:shared+ and +:per_controller+ keys
        def to_h
          { shared: @shared.sort, per_controller: @per_controller.transform_values(&:sort) }
        end
      end
      private_constant :PartialIndex

      # Initializes the view introspector and path resolver.
      #
      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
        @path_resolver = PathResolver.new(app)
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
      rescue StandardError => error
        { error: error.message }
      end

      private

      def root
        app.root.to_s
      end

      # Returns the first configured logical +app/views+ directory.
      #
      # @return [String, nil] absolute view directory path
      def views_dir
        @path_resolver.directories_for('app/views').first
      end

      def extract_layouts
        @path_resolver.glob_for('app/views', 'layouts/*').filter_map do |path|
          File.basename(path) if File.file?(path)
        end.sort
      end

      def extract_templates
        templates = TemplateIndex.new
        @path_resolver.glob_for('app/views', '**/*').each do |path|
          next if File.directory?(path)

          templates.add(view_relative_path(path))
        end

        templates.to_h
      end

      def extract_partials
        partials = PartialIndex.new

        @path_resolver.glob_for('app/views', '**/_*').each do |path|
          partials.add(view_relative_path(path))
        end

        partials.to_h
      end

      def extract_helpers
        helpers = @path_resolver.files_for('app/helpers', extension: 'rb').filter_map do |path|
          relative = logical_relative_path(path, logical_path: 'app/helpers')
          content = File.read(path)
          methods = content.scan(/^\s*def\s+(\w+)/).flatten
          {
            file: relative,
            methods: methods
          }
        rescue StandardError
          nil
        end

        helpers.sort_by { |helper| helper[:file] }
      end

      def extract_view_components
        @path_resolver.files_for('app/components', extension: 'rb').filter_map do |path|
          logical_relative_path(path, logical_path: 'app/components').sub(/\.rb\z/, '')
        end.sort
      end

      def detect_template_engines
        extensions = @path_resolver.glob_for('app/views', '**/*').filter_map do |path|
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

      def view_relative_path(path)
        logical_relative_path(path, logical_path: 'app/views')
      end

      # Converts an absolute path to a path relative to the requested logical Rails path.
      #
      # @param path [String] absolute file path
      # @param logical_path [String] logical Rails path key
      # @return [String] relative path beneath the logical path
      def logical_relative_path(path, logical_path:)
        @path_resolver.logical_file_path(path, logical_path: logical_path).delete_prefix("#{logical_path}/")
      end
    end
  end
end
