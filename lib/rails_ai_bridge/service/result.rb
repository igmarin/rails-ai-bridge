# frozen_string_literal: true

module RailsAiBridge
  class Service
    # Result object returned by all service calls.
    #
    # Provides a standardized way to return success/failure states with associated
    # data and error messages. Supports method chaining via on_success/on_failure.
    # {#errors} and {#metadata} are defensive copies, frozen, so callers do not share
    # mutable default state and cannot mutate the internal arrays/hashes in place.
    #
    # @example Success Result
    #   result = Service::Result.new(true, data: {users: ["alice", "bob"]})
    #   result.success? # => true
    #   result.data      # => {users: ["alice", "bob"]}
    #
    # @example Failure Result
    #   result = Service::Result.new(false, errors: ["Invalid input"])
    #   result.failure? # => true
    #   result.errors   # => ["Invalid input"]
    #
    # @example Chaining
    #   result.on_success { |r| puts "Success: #{r.data}" }
    #          .on_failure { |r| puts "Error: #{r.errors.first}" }
    class Result
      attr_reader :success, :data, :errors, :metadata

      # Initialize a new result object.
      #
      # @param success [Boolean] whether the operation succeeded
      # @param data [Object] result data (nil for failures)
      # @param errors [Array<String>, String, nil] error messages; `nil` means no errors (same as empty).
      #   Stored as a duplicated, frozen Array so defaults are not shared across instances.
      # @param metadata [Hash, nil] additional metadata; `nil` is treated like `{}`. A duplicate is frozen
      #   so the caller's Hash is never frozen in place.
      def initialize(success, data: nil, errors: nil, metadata: nil)
        @success = success
        @data = data
        @errors = Array(errors).dup.freeze
        @metadata = (metadata || {}).dup.freeze
      end

      # Check if the operation was successful.
      #
      # @return [Boolean] true if successful
      def success?
        success
      end

      # Check if the operation failed.
      #
      # @return [Boolean] true if failed
      def failure?
        !success
      end

      # Execute block if successful, enabling method chaining.
      #
      # @yield [Result] the result object
      # @yieldparam result [Result] the result object
      # @return [Result] self for chaining
      def on_success(&block)
        return self unless success && block
        tap(&block)
      end

      # Execute block if failed, enabling method chaining.
      #
      # @yield [Result] the result object
      # @yieldparam result [Result] the result object
      # @return [Result] self for chaining
      def on_failure(&block)
        return self unless failure? && block
        tap(&block)
      end

      # Convert result to hash representation.
      #
      # @return [Hash] hash with success, data, errors, and metadata
      def to_h
        {
          success: success,
          data: data,
          errors: errors,
          metadata: metadata
        }
      end
    end
  end
end
