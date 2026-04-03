# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Models section with associations, validations, and enums.
      #
      # @see Formatters::Providers::SectionFormatter
      class ModelsFormatter < SectionFormatter
        section :models

        private

        def render(data)
          lines = [ "## Models (#{data.size})" ]
          data.each do |name, info|
            next if info[:error]
            assocs = (info[:associations] || []).map { |a| "#{a[:type]} :#{a[:name]}" }.join(", ")
            lines << "### #{name}"
            lines << "- Table: `#{info[:table_name]}`" if info[:table_name]
            lines << "- Associations: #{assocs}" if assocs.present?
            if info[:validations]&.any?
              vals = info[:validations].map { |v| "#{v[:kind]} on #{v[:attributes].join(', ')}" }.join("; ")
              lines << "- Validations: #{vals}"
            end
            lines << "- Enums: #{info[:enums].keys.join(', ')}" if info[:enums]&.any?
          end
          lines.join("\n")
        end
      end
    end
  end
end
