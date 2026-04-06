# frozen_string_literal: true

module RailsAiBridge
  module Services
    # Application service for reading and updating the gem's global configuration.
    #
    # Serializes access to {RailsAiBridge.configuration} with a class-level mutex so
    # concurrent threads cannot interleave reads and in-place updates performed in the
    # optional block. Standard errors are captured and returned as a failed
    # {RailsAiBridge::Service::Result} rather than raised.
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
      # @api private
      MUTEX = Mutex.new

      # Class-level entry point; instantiates the service and delegates to {#call}.
      #
      # @yield [config] Optional block to mutate configuration in place
      # @yieldparam config [RailsAiBridge::Configuration] Current configuration singleton
      # @return [RailsAiBridge::Service::Result] Success with `data` set to the configuration,
      #   or failure with `errors` populated
      def self.call(&block)
        new.call(&block)
      end

      # Returns the current configuration, optionally yielding it for in-place updates.
      #
      # The configuration read and optional block run inside {MUTEX} so the sequence is atomic
      # with respect to other calls to this service in the same process.
      #
      # @yield [config] Optional block for in-place configuration changes
      # @yieldparam config [RailsAiBridge::Configuration] The current configuration object
      # @return [RailsAiBridge::Service::Result] On success, `data` is the configuration; on
      #   `StandardError`, `success?` is false and `errors` contains the message
      def call(&block)
        MUTEX.synchronize do
          config = RailsAiBridge.configuration
          block&.call(config)
          Service::Result.new(true, data: config)
        end
      rescue StandardError => e
        Service::Result.new(false, errors: [ e.message ])
      end
    end
  end
end
