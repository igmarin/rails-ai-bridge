# frozen_string_literal: true

module RailsAiBridge
  module Services
    # Service for generating context files from introspection data.
    #
    # Uses serializers to convert introspection results into various output formats
    # (Claude, Cursor, Copilot, etc.) and handles file writing operations.
    #
    # @example Generate all context files
    #   result = Services::ContextGenerationService.call(introspection_data)
    #   if result.success?
    #     puts "Generated #{result.data[:written].count} files"
    #   end
    #
    # @example Generate specific format
    #   result = Services::ContextGenerationService.call(introspection_data, format: :claude)
    class ContextGenerationService < RailsAiBridge::Service
      def self.call(context_data, format: :all, serializer_class: Serializers::ContextFileSerializer)
        new(context_data, serializer_class: serializer_class, format: format).call
      end

      # Initialize the service with context data and serialization options.
      #
      # @param context_data [Hash] introspection data to serialize
      # @param serializer_class [Class] serializer class to use
      # @param format [Symbol] output format (:all, :claude, :cursor, etc.)
      def initialize(context_data, serializer_class: Serializers::ContextFileSerializer, format: :all)
        @context_data = context_data
        @serializer_class = serializer_class
        @format = format
      end

      # Generate context files using the configured serializer.
      #
      # @return [Service::Result] result with file operation results
      def call
        serializer = @serializer_class.new(@context_data, format: @format)
        serialization_result = serializer.call

        Service::Result.new(true, data: serialization_result)
      rescue StandardError => e
        Service::Result.new(false, errors: [ e.message ])
      end
    end
  end
end
