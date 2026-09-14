# frozen_string_literal: true

module RailsAiBridge
  module Services
    # Application service for generating context files from introspection data.
    #
    # Delegates to a serializer (default {RailsAiBridge::Serializers::ContextFileSerializer}) and
    # normalizes successful results to a stable `data` shape: `{ written: Array, skipped: Array }`,
    # even when the serializer returns a partial hash, a non-hash, or `nil`. Failures are returned
    # as a failed {RailsAiBridge::Service::Result} rather than raised.
    #
    # @example Generate all context files
    #   result = Services::ContextGenerationService.call(introspection_data)
    #   if result.success?
    #     puts "Generated #{result.data[:written].count} files"
    #   end
    #
    # @example Generate specific format
    #   result = Services::ContextGenerationService.call(introspection_data, format: :claude)
    class ContextGenerationService < RailsAiBridge::Service
      # Class-level entry point with explicit serializer and format. The source fingerprint
      # is always computed at call time via {Fingerprinter.source_fingerprint}; to inject a
      # fingerprint (or serializer class) directly, use {#initialize}.
      #
      # @param context_data [Hash] Introspection data to pass to the serializer
      # @param format [Symbol] Output format (e.g. `:all`, `:claude`, `:cursor`)
      # @param serializer_class [Class] Serializer class; must respond to
      #   `#new(context_data, fingerprint:, **write_options)` (+:format+ is passed as a
      #   write option) and instances must respond to `#call`
      # @return [RailsAiBridge::Service::Result] On success, `data` is `{ written: Array, skipped: Array }`;
      #   on `StandardError`, `success?` is false and `errors` contains the message
      def self.call(context_data, format: :all, serializer_class: Serializers::ContextFileSerializer)
        new(context_data, serializer_class: serializer_class, format: format).call
      end

      # @param context_data [Hash] Introspection data to serialize
      # @param context_data [Hash] Introspection data to serialize
      # @param serializer_class [Class] Serializer class (see {.call})
      # @param format [Symbol] Output format passed to the serializer
      # @param fingerprint [String, nil] source fingerprint passed to the serializer; when
      #   nil, computed from +Fingerprinter.source_fingerprint(AppScope.current_app)+ at call time
      def initialize(context_data, serializer_class: Serializers::ContextFileSerializer, format: :all, fingerprint: nil)
        super()
        @context_data = context_data
        @serializer_class = serializer_class
        @format = format
        @fingerprint = fingerprint
      end

      # Runs the serializer and wraps the outcome in a {RailsAiBridge::Service::Result}.
      #
      # Successful `data` always uses symbol keys `:written` and `:skipped` with array values, derived
      # only from symbol keys on a Hash return value from the serializer.
      #
      # @return [RailsAiBridge::Service::Result] Success with normalized `data`, or failure with errors
      def call
        fingerprint = @fingerprint || Fingerprinter.source_fingerprint(AppScope.current_app)
        serializer = @serializer_class.new(@context_data, format: @format, fingerprint: fingerprint)
        serialization_result = serializer.call

        normalized = {
          written: Array(serialization_result.is_a?(Hash) ? serialization_result[:written] : nil),
          skipped: Array(serialization_result.is_a?(Hash) ? serialization_result[:skipped] : nil)
        }

        Service::Result.new(true, data: normalized)
      rescue StandardError => error
        Service::Result.new(false, errors: [error.message])
      end
    end
  end
end
