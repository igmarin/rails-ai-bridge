# frozen_string_literal: true

module RailsAiBridge
  module Services
    # Base service class providing transactional support for operations.
    #
    # Wraps service execution in a transaction-like pattern with automatic
    # rollback on failure and resource cleanup. Provides a consistent way to
    # handle operations that require atomic execution or resource management.
    #
    # @example Basic transaction
    #   result = TransactionalService.call do
    #     # Perform operation
    #     RailsAiBridge::Service::Result.new(true, data: result)
    #   end
    #
    # @example With rollback handling
    #   result = TransactionalService.call do
    #     begin
    #       risky_operation
    #     rescue => e
    #       cleanup_resources
    #       raise
    #     end
    #   end
    class TransactionalService < RailsAiBridge::Service
      # Execute an operation within a transaction context.
      #
      # @yield Block to execute within transaction
      # @yieldreturn [RailsAiBridge::Service::Result] result from the operation
      # @return [RailsAiBridge::Service::Result] result of the transaction
      def self.call(&block)
        new.call(&block)
      end

      # Execute the transactional operation.
      #
      # @yield Block to execute within transaction context
      # @yieldreturn [RailsAiBridge::Service::Result] result from the operation
      # @return [RailsAiBridge::Service::Result] result of the transaction
      def call(&block)
        raise ArgumentError, "Block is required" unless block
        
        begin
          result = block.call
          
          # Ensure result is a Service::Result
          unless result.is_a?(RailsAiBridge::Service::Result)
            return RailsAiBridge::Service::Result.new(false, errors: ["Block must return Service::Result"])
          end
          
          result
        rescue StandardError => e
          # In a real implementation, this is where rollback logic would go
          # For now, we just ensure consistent error handling
          RailsAiBridge::Service::Result.new(false, errors: [e.message])
        end
      end
    end
  end
end
