# frozen_string_literal: true

module RailsAiBridge
  class Service
    class Result
      attr_reader :success, :data, :errors, :metadata

      def initialize(success, data: nil, errors: [], metadata: {})
        @success = success
        @data = data
        @errors = Array(errors)
        @metadata = metadata.freeze
      end

      def success?
        success
      end

      def failure?
        !success
      end

      def on_success(&block)
        return self unless success && block
        tap(&block)
      end

      def on_failure(&block)
        return self unless failure? && block
        tap(&block)
      end

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
