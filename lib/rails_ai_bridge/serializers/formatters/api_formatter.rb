# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the API Layer section with versioning, serializers, and GraphQL.
      class ApiFormatter < Base
        # @return [String, nil]
        def call
          data = context[:api]
          return unless data
          return if data[:error]

          lines = [ "## API Layer" ]
          lines << "- API-only mode: #{data[:api_only]}"
          lines << "- API versions: #{data[:api_versioning].join(', ')}" if data[:api_versioning]&.any?
          if data[:serializers]&.any?
            lines << "- Jbuilder templates: #{data[:serializers][:jbuilder]}" if data[:serializers][:jbuilder]
            if data[:serializers][:serializer_classes]&.any?
              lines << "- Serializers: #{data[:serializers][:serializer_classes].join(', ')}"
            end
          end
          if data[:graphql]
            lines << "### GraphQL"
            lines << "- Types: #{data[:graphql][:types]}, Mutations: #{data[:graphql][:mutations]}"
          end
          lines.join("\n")
        end
      end
    end
  end
end
