# frozen_string_literal: true

module RailsAiBridge
  module Services
    # Application service for running the app {RailsAiBridge::Introspector} behind {RailsAiBridge::Service}.
    #
    # Treats a top-level `:error` key or any nested value that is a Hash containing `:error` as failure
    # (per-introspector errors). Otherwise returns success with the introspection Hash as `data`.
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
      # @param app [Rails::Application] Rails application to introspect
      # @param only [Array<Symbol>, nil] forwarded to {RailsAiBridge::Introspector#call}
      # @param introspector_class [Class] class that responds to `#new(app)` and `#call(only:)`
      # @return [RailsAiBridge::Service::Result] success with introspection data or failure with errors
      def self.call(app, only: nil, introspector_class: Introspector)
        new(app, introspector_class: introspector_class).call(only: only)
      end

      # @param app [Rails::Application] the Rails application to introspect
      # @param introspector_class [Class] introspector class to use (defaults to {RailsAiBridge::Introspector})
      def initialize(app, introspector_class: Introspector)
        super()
        @app = app
        @introspector_class = introspector_class
      end

      # Performs introspection and wraps the outcome in a {RailsAiBridge::Service::Result}.
      #
      # Fails when the introspector returns a non-Hash, a top-level `:error` entry, or when any entry's
      # value is a Hash with an `:error` key (nested per-introspector failure). In the nested case,
      # `errors` contains strings `"<key>: <message>"` for each failing entry.
      #
      # @param only [Array<Symbol>, nil] optional list of introspector keys to run
      # @return [RailsAiBridge::Service::Result] success with introspection Hash as `data`, or failure
      #   with messages; `StandardError` from the introspector is captured (not raised)
      def call(only: nil)
        introspector = @introspector_class.new(@app)
        introspection_result = introspector.call(only: only)

        unless introspection_result.is_a?(Hash)
          return Service::Result.new(false,
                                     errors: ['Introspector must return a Hash'])
        end
        if introspection_result.key?(:error)
          return Service::Result.new(false,
                                     errors: ["Introspector returned error: #{introspection_result[:error]}"])
        end

        nested_errors = introspection_result.filter_map do |name, payload|
          next unless payload.is_a?(Hash) && payload.key?(:error)

          "#{name}: #{payload[:error]}"
        end
        return Service::Result.new(false, errors: nested_errors) if nested_errors.any?

        Service::Result.new(true, data: introspection_result)
      rescue StandardError => e
        Service::Result.new(false, errors: [e.message])
      end
    end
  end
end
