# frozen_string_literal: true

module RailsAiBridge
  class AppIntrospectionService < Service
    def self.call(app, only: nil, introspector_class: Introspector)
      new(app, introspector_class: introspector_class).call(only: only)
    end

    def initialize(app, introspector_class: Introspector)
      @app = app
      @introspector_class = introspector_class
    end

    def call(only: nil)
      introspector = @introspector_class.new(@app)
      introspection_result = introspector.call(only: only)
      
      Service::Result.new(true, data: introspection_result)
    rescue StandardError => e
      Service::Result.new(false, errors: [e.message])
    end
  end
end
