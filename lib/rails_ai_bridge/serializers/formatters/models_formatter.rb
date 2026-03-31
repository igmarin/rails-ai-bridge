# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Models section with associations, validations, and enums.
      class ModelsFormatter < Base
        # @return [String, nil]
        def call
          models = context[:models]
          return unless models
          return if models.is_a?(Hash) && models[:error]

          lines = [ "## Models (#{models.size})" ]
          models.each do |name, data|
            next if data[:error]
            assocs = (data[:associations] || []).map { |a| "#{a[:type]} :#{a[:name]}" }.join(", ")
            lines << "### #{name}"
            lines << "- Table: `#{data[:table_name]}`" if data[:table_name]
            lines << "- Associations: #{assocs}" if assocs.present?
            if data[:validations]&.any?
              vals = data[:validations].map { |v| "#{v[:kind]} on #{v[:attributes].join(', ')}" }.join("; ")
              lines << "- Validations: #{vals}"
            end
            lines << "- Enums: #{data[:enums].keys.join(', ')}" if data[:enums]&.any?
          end
          lines.join("\n")
        end
      end
    end
  end
end
