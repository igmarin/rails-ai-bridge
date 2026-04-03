# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders a high-level overview of the Rails application.
      #
      # @see Formatters::Providers::SectionFormatter
      class AppOverviewFormatter < Formatters::Providers::SectionFormatter
        section :app_overview

        private

        def render(data)
          return unless data[:app_name] || data[:rails_version]

          lines = [ "# Application Overview", "" ]
          lines << "- **Name:** `#{data[:app_name]}`" if data[:app_name]
          lines << "- **Rails:** `#{data[:rails_version]}`" if data[:rails_version]
          lines << "- **Ruby:** `#{data[:ruby_version]}`" if data[:ruby_version]
          lines << "- **Environment:** `#{data[:environment]}`" if data[:environment]
          lines << "- **Database:** `#{data[:database_adapter]}`" if data[:database_adapter]
          lines.join("\n")
        end
      end
    end
  end
end
