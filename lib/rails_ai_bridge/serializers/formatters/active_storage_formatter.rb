# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Active Storage section with attachment types and services.
      class ActiveStorageFormatter < Base
        # @return [String, nil]
        def call
          data = context[:active_storage]
          return unless data
          return if data[:error]
          return unless data[:attachments]&.any?

          lines = [ "## Active Storage" ]
          data[:attachments].each { |a| lines << "- `#{a[:model]}` #{a[:type]} :#{a[:name]}" }
          lines << "- Storage services: #{data[:storage_services].join(', ')}" if data[:storage_services]&.any?
          lines.join("\n")
        end
      end
    end
  end
end
