# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers Active Storage usage: attachments, storage service config,
    # direct upload detection.
    class ActiveStorageIntrospector
      attr_reader :app, :path_resolver

      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
        @path_resolver = PathResolver.new(app)
      end

      # Builds a read-only summary of Active Storage usage.
      #
      # @return [Hash] Active Storage installation, attachment, service, and direct-upload metadata
      def call
        {
          installed: defined?(ActiveStorage) ? true : false,
          attachments: extract_attachments,
          storage_services: extract_storage_services,
          direct_upload: detect_direct_upload
        }
      rescue StandardError => error
        { error: error.message }
      end

      private

      def root
        app.root.to_s
      end

      def extract_attachments
        attachments = []
        path_resolver.files_for('app/models', extension: 'rb').each do |path|
          content = File.read(path)
          model_name = File.basename(path, '.rb').camelize

          content.scan(/has_one_attached\s+:(\w+)/).each do |match|
            attachments << { model: model_name, name: match[0], type: 'has_one_attached' }
          end

          content.scan(/has_many_attached\s+:(\w+)/).each do |match|
            attachments << { model: model_name, name: match[0], type: 'has_many_attached' }
          end
        end

        attachments.sort_by { |a| [a[:model], a[:name]] }
      rescue StandardError
        []
      end

      def extract_storage_services
        config_path = File.join(root, 'config/storage.yml')
        return [] unless File.exist?(config_path)

        require 'yaml'
        config = YAML.load_file(config_path, permitted_classes: [Symbol], aliases: true) || {}
        config.keys.sort
      rescue StandardError
        []
      end

      def detect_direct_upload
        direct_upload_files.any? do |file|
          next false if File.directory?(file)

          File.read(file).match?(/direct.upload|DirectUpload|direct_upload/)
        rescue StandardError
          false
        end
      end

      def direct_upload_files
        path_resolver.glob_for('app/views', '**/*') + path_resolver.glob_for('app/javascript', '**/*')
      rescue StandardError
        []
      end
    end
  end
end
