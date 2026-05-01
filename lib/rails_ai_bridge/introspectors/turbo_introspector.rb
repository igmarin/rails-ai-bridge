# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Scans for Hotwire/Turbo usage: frames, streams, model broadcasts.
    class TurboIntrospector
      attr_reader :app

      # Initializes the Turbo introspector and path resolver.
      #
      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
        @path_resolver = PathResolver.new(app)
      end

      def call
        {
          turbo_frames: extract_turbo_frames,
          turbo_streams: extract_turbo_stream_templates,
          model_broadcasts: extract_model_broadcasts
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

      def extract_turbo_frames
        frames = []
        @path_resolver.glob_for('app/views', '**/*.{erb,haml,slim}').each do |path|
          content = File.read(path)
          relative = view_relative_path(path)

          content.scan(/turbo_frame_tag\s+[:"']?(\w+)/).each do |match|
            frames << { id: match[0], file: relative }
          end
        end

        frames.sort_by { |f| f[:id] }
      rescue StandardError
        []
      end

      def extract_turbo_stream_templates
        @path_resolver.glob_for('app/views', '**/*.turbo_stream.erb').filter_map do |path|
          view_relative_path(path)
        end.sort
      end

      def extract_model_broadcasts
        broadcasts = []
        @path_resolver.files_for('app/models', extension: 'rb').each do |path|
          content = File.read(path)
          model_name = File.basename(path, '.rb').camelize

          broadcast_methods = content.scan(/\b(broadcasts_to|broadcasts_refreshes_to|broadcasts)\b/).flatten.uniq
          next if broadcast_methods.empty?

          broadcasts << { model: model_name, methods: broadcast_methods }
        end

        broadcasts.sort_by { |b| b[:model] }
      rescue StandardError
        []
      end

      # Converts an absolute view path to a stable path relative to logical +app/views+.
      #
      # @param path [String] absolute source path
      # @return [String] path relative to the logical view directory
      def view_relative_path(path)
        @path_resolver.logical_file_path(path, logical_path: 'app/views').delete_prefix('app/views/')
      end
    end
  end
end
