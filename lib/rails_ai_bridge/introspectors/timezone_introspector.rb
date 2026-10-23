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
    # @example Output shape (static parse, Rails not booted)
    #   { time_zone: "UTC", time_zone_confirmed: false }
    class TimezoneIntrospector
      attr_reader :app

      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
      end

      # Builds timezone facts. +Time.zone+ is set by Rails at boot from
      # +config.time_zone+; it is nil in a static parse, in which case the
      # configured value cannot be confirmed.
      #
      # @return [Hash] timezone facts, or +{ error: message }+ on failure
      def call
        configured = app.config.time_zone.to_s
        { time_zone: configured, time_zone_confirmed: Time.zone&.to_s == configured }
      rescue StandardError => error
        { error: error.message }
      end
    end
  end
end
