# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Database Seeds section.
      #
      # @see Formatters::Providers::SectionFormatter
      class SeedsFormatter < Formatters::Providers::SectionFormatter
        section :seeds

        private

        def render(data)
          lines = [ "## Database Seeds" ]
          if data[:seeds_file]
            lines << "- Seeds file: #{data[:seeds_file][:exists] ? 'exists' : 'missing'}"
            lines << "- Uses Faker: yes" if data[:seeds_file][:uses_faker]
            lines << "- Environment-conditional: yes" if data[:seeds_file][:environment_conditional]
          end
          lines << "- Models seeded: #{data[:models_seeded].join(', ')}" if data[:models_seeded]&.any?

          if data[:seed_files]&.any?
            lines << "### Seed Files"
            data[:seed_files].each { |f| lines << "- `#{f[:file]}`" }
          end

          lines.join("\n")
        end
      end
    end
  end
end
