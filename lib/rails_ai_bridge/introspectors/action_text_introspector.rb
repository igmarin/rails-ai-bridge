# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers Action Text usage: rich text fields per model.
    class ActionTextIntrospector
      attr_reader :app, :path_resolver

      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
        @path_resolver = PathResolver.new(app)
      end

      # Builds a read-only summary of Action Text usage.
      #
      # @return [Hash] Action Text installation flag and rich text field metadata
      def call
        {
          installed: defined?(ActionText) ? true : false,
          rich_text_fields: extract_rich_text_fields
        }
      rescue StandardError => error
        { error: error.message }
      end

      private

      def extract_rich_text_fields
        fields = []
        path_resolver.files_for('app/models', extension: 'rb').each do |path|
          content = File.read(path)
          model_name = File.basename(path, '.rb').camelize

          content.scan(/has_rich_text\s+:(\w+)/).each do |match|
            fields << { model: model_name, field: match[0] }
          end
        end

        fields.sort_by { |f| [f[:model], f[:field]] }
      rescue StandardError
        []
      end
    end
  end
end
