# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Scans for Hotwire/Turbo usage: frames, streams, model broadcasts.
    class TurboIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
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

      def views_dir
        File.join(root, 'app/views')
      end

      def extract_turbo_frames
        return [] unless Dir.exist?(views_dir)

        frames = []
        Dir.glob(File.join(views_dir, '**/*.{erb,haml,slim}')).each do |path|
          content = File.read(path)
          relative = path.sub("#{views_dir}/", '')

          content.scan(/turbo_frame_tag\s+[:"']?(\w+)/).each do |match|
            frames << { id: match[0], file: relative }
          end
        end

        frames.sort_by { |f| f[:id] }
      rescue StandardError
        []
      end

      def extract_turbo_stream_templates
        return [] unless Dir.exist?(views_dir)

        Dir.glob(File.join(views_dir, '**/*.turbo_stream.erb')).filter_map do |path|
          path.sub("#{views_dir}/", '')
        end.sort
      end

      def extract_model_broadcasts
        models_dir = File.join(root, 'app/models')
        return [] unless Dir.exist?(models_dir)

        broadcasts = []
        Dir.glob(File.join(models_dir, '**/*.rb')).each do |path|
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
    end
  end
end
