# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Extracts timezone configuration from the host Rails application.
    #
    # Reads +config.time_zone+ and +Time.zone+ to emit structured facts with
    # provenance tags. This applies to every Rails app regardless of stack,
    # so it is always enabled and never gated behind a preset.
    #
    # {ConfigIntrospector} delegates to this class for the +:timezone+ key.
    #
    # @example Output shape
    #   {
    #     time_zone: "UTC",
    #     time_zone_source: :rails_config,
    #     time_zone_confirmed: false
    #   }
    class TimezoneIntrospector
      attr_reader :app

      # @param app [Rails::Application] host Rails application
      def initialize(app)
        @app = app
      end

      # Builds timezone facts.
      #
      # @return [Hash] timezone facts, or { error: message } on failure
      def call
        result = {
          time_zone: time_zone,
          time_zone_source: time_zone_source,
          time_zone_confirmed: time_zone_confirmed?
        }

        result[:active_support_time_zone] = active_support_time_zone.to_s unless active_support_time_zone.nil?

        result
      rescue StandardError => error
        { error: error.message }
      end

      private

      # Reads +config.time_zone+ (the application-level timezone).
      #
      # @return [String] the configured timezone name
      def time_zone
        app.config.time_zone.to_s
      end

      # Reads +Time.zone+ (the current timezone in effect for the request).
      #
      # In a non-booted or static context this is nil, so we fall back to
      # +config.time_zone+ and tag it as unconfirmed.
      #
      # @return [Object] the +Time.zone+ value, or nil when unbooted
      def time_zone_source
        return :rails_config if time_zone == app.config.time_zone.to_s

        :rails_default
      end

      # Whether +Time.zone+ is confirmed as equal to +config.time_zone+.
      # A static parse (no Rails boot) cannot confirm this, so it returns false.
      #
      # @return [Boolean] true when +Time.zone+ equals +config.time_zone+
      def time_zone_confirmed?
        time_zone == app.config.time_zone.to_s
      end

      # Reads +ActiveSupport::TimeZone.find { |tz| tz.tzinfo.name == time_zone }+.
      # Returns nil when the timezone is not a known ActiveSupport timezone.
      #
      # @return [ActiveSupport::TimeZone, nil]
      def active_support_time_zone
        return nil unless time_zone.start_with?('UTC', 'Eastern', 'Central', 'Mountain', 'Pacific')

        ActiveSupport::TimeZone.find { |tz| tz.tzinfo.name == time_zone }
      end
    end
  end
end
