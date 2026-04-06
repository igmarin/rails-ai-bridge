# frozen_string_literal: true

module RailsAiBridge
  class ContextGenerationService < Service
    def self.call(context_data, format: :all, serializer_class: Serializers::ContextFileSerializer)
      new(context_data, serializer_class: serializer_class, format: format).call
    end

    def initialize(context_data, serializer_class: Serializers::ContextFileSerializer, format: :all)
      @context_data = context_data
      @serializer_class = serializer_class
      @format = format
    end

    def call
      serializer = @serializer_class.new(@context_data, format: @format)
      serialization_result = serializer.call

      Service::Result.new(true, data: serialization_result)
    rescue StandardError => e
      Service::Result.new(false, errors: [ e.message ])
    end
  end
end
