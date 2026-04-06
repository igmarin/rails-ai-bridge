# frozen_string_literal: true

module RailsAiBridge
  module Services
    # Service for performing application introspection.
    #
    # Wraps the introspector functionality in a service pattern, providing
    # consistent error handling and result formatting.
    #
    # @example Basic usage
    #   result = Services::AppIntrospectionService.call(Rails.application)
    #   if result.success?
    #     puts "Introspection complete: #{result.data.keys}"
    #   else
    #     puts "Error: #{result.errors.first}"
    #   end
    #
    # @example With specific introspectors
    #   result = Services::AppIntrospectionService.call(Rails.application, only: [:models, :routes])
    class AppIntrospectionService < RailsAiBridge::Service
      def self.call(app, only: nil, introspector_class: Introspector)
        new(app, introspector_class: introspector_class).call(only: only)
      end

      # Initialize the service with a Rails application and optional introspector class.
      #
      # @param app [Rails::Application] the Rails application to introspect
      # @param introspector_class [Class] introspector class to use (defaults to Introspector)
      def initialize(app, introspector_class: Introspector)
        @app = app
        @introspector_class = introspector_class
      end

      # Perform introspection and return results.
      #
      # @param only [Array<Symbol>, nil] optional list of introspector keys to run
      # @return [Service::Result] result with introspection data or errors
      def call(only: nil)
        introspector = @introspector_class.new(@app)
        introspection_result = introspector.call(only: only)

        return Service::Result.new(false, errors: [ "Introspector must return a Hash" ]) unless introspection_result.is_a?(Hash)
        return Service::Result.new(false, errors: [ "Introspector returned error: #{introspection_result[:error]}" ]) if introspection_result.key?(:error)

        Service::Result.new(true, data: introspection_result)
      rescue StandardError => e
        Service::Result.new(false, errors: [ e.message ])
      end
    end
  end
end
