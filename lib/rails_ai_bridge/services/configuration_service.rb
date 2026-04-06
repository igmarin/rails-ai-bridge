# frozen_string_literal: true

module RailsAiBridge
  class ConfigurationService < Service
    def self.call(&block)
      new.call(&block)
    end

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
