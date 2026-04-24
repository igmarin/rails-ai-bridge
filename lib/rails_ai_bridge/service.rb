# frozen_string_literal: true

module RailsAiBridge
  # Base service class providing a standardized interface for all services.
  #
  # Services follow the command pattern with a single public method (.call)
  # that returns a Service::Result object. This provides consistent error
  # handling and result structure across all services.
  #
  # @example Basic Usage
  #   class MyService < RailsAiBridge::Service
  #     def call
  #       # business logic
  #       Service::Result.new(true, data: "result")
  #     end
  #   end
  #
  #   result = MyService.call(arg1, kwarg1: "value")
  #   if result.success?
  #     puts result.data
  #   else
  #     puts "Error: #{result.errors.first}"
  #   end
  class Service
    class << self
      # Class-level entry point that creates an instance and calls it.
      #
      # @param args [Array] positional arguments passed to initialize
      # @param kwargs [Hash] keyword arguments passed to initialize
      # @return [Service::Result] result from the service call
      def call(*, **)
        new(*, **).call
      end
    end

    # Initialize the service with provided arguments.
    #
    # @param args [Array] positional arguments
    # @param kwargs [Hash] keyword arguments
    def initialize(*args, **kwargs)
      # Standard initialization
      @args = args
      @kwargs = kwargs
    end

    # Execute the service and return a result.
    #
    # Subclasses must override this method to implement specific business logic.
    #
    # @return [Service::Result] result object indicating success or failure
    # @raise [NotImplementedError] if not overridden by subclass
    def call
      raise NotImplementedError, "#{self.class} must implement #call"
    end
  end
end
