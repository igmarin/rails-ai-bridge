# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts timezone configuration from the host Rails application.
    #
    # Reads +config.time_zone+ and compares it with +Time.zone+ (which Rails
    # sets at boot from +config.time_zone+) to emit structured facts. This
    # applies to every Rails app regardless of stack, so it always runs as
    # part of {ConfigIntrospector}; it is not a preset-gated section.
    #
    # @example Output shape (booted app, matching zone)
    #   { time_zone: "UTC", time_zone_confirmed: true }
    #
    # @example Output shape (configured app, runtime zone unavailable)
    #   { time_zone: "UTC", time_zone_confirmed: false }
    class TimezoneIntrospector
      # @return [Rails::Application] host Rails application
      attr_reader :app

      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
      end

      # Builds timezone facts. +Time.zone+ is set by Rails at boot from
      # +config.time_zone+. Confirmation compares IANA identifiers so Rails
      # names and their IANA identifiers agree. An unavailable or
      # different runtime zone leaves the configured value unconfirmed.
      #
      # @return [Hash] timezone facts, or +{ error: message }+ on failure
      def call
        configured = app.config.time_zone.to_s
        runtime_identifier = Time.zone&.tzinfo&.identifier
        {
          time_zone: configured,
          time_zone_confirmed: (runtime_identifier && runtime_identifier == ActiveSupport::TimeZone[configured]&.tzinfo&.identifier) || false
        }
      rescue StandardError => error
        { error: error.message }
      end
    end
  end
end
