# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the DevOps & CI/CD section.
      #
      # @see Formatters::Providers::SectionFormatter
      class DevopsFormatter < Formatters::Providers::SectionFormatter
        section :devops

        private

        def render(data)
          return unless data[:ci_cd]&.any? || data[:docker] || data[:kamal] ||
                        data[:procfile_entries]&.any? || data[:health_check_route]

          lines = [ "## DevOps & CI/CD", "" ]
          lines << "- **CI/CD:** `#{data[:ci_cd].join(", ")}`" if data[:ci_cd]&.any?
          lines << "- **Docker:** `#{data[:docker]}`" if data[:docker]
          lines << "- **Kamal:** yes" if data[:kamal]

          if data[:procfile_entries]&.any?
            lines << "" << "### Procfile"
            data[:procfile_entries].each { |p| lines << "- `#{p[:name]}: #{p[:command]}`" }
          end

          if data[:health_check_route]
            lines << "" << "### Health Check"
            lines << "- Route: `#{data[:health_check_route]}`"
          end
          lines.join("\n")
        end
      end
    end
  end
end
