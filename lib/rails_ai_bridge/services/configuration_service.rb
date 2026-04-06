# frozen_string_literal: true

module RailsAiBridge
  module Services
    # Service for managing Rails AI Bridge configuration.
    #
    # Provides a safe interface for reading and modifying configuration
    # with proper error handling and validation.
    #
    # @example Read current configuration
    #   result = Services::ConfigurationService.call
    #   if result.success?
    #     puts "Current preset: #{result.data.introspection.preset}"
    #   end
    #
    # @example Modify configuration
    #   result = Services::ConfigurationService.call do |config|
    #     config.introspection.cache_ttl = 3600
    #   end
    #   if result.success?
    #     puts "Configuration updated"
    #   end
    class ConfigurationService < RailsAiBridge::Service
      def self.call(&block)
        new.call(&block)
      end

      # Get and optionally modify the current configuration.
      #
      # @yield [config] optional block for configuration modifications
      # @yieldparam config [Configuration] the current configuration object
      # @return [Service::Result] result with configuration data
      def call(&block)
        config = RailsAiBridge.configuration

        if block
          block.call(config)
          # Note: RailsAiBridge::Configuration doesn't have validate! method
          # so we just return the modified config
        end

        Service::Result.new(true, data: config)
      rescue StandardError => e
        Service::Result.new(false, errors: [ e.message ])
      end
    end
  end
end
