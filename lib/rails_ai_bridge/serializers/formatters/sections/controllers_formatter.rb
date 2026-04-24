# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Controllers section.
      #
      # @see Formatters::Providers::SectionFormatter
      class ControllersFormatter < SectionFormatter
        section :controllers

        private

        def render(data)
          return unless data[:controllers]&.any?

          lines = ["## Controllers (#{data[:controllers].size})", '']
          data[:controllers].sort_by { |name, _| name }.each do |name, info|
            next if info[:error] # Skip controllers with introspection errors

            lines << "### #{name}"
            lines << "- Parent: `#{info[:parent_class]}`" if info[:parent_class]
            lines << '- API controller: yes' if info[:api_controller]
            lines << "- Actions: #{info[:actions].map { |a| "`#{a}`" }.join(', ')}" if info[:actions]&.any?

            lines << "- Filters: #{info[:filters].map { |f| "`#{f[:kind]} #{f[:name]}`" }.join(', ')}" if info[:filters]&.any?
            lines << "- Strong params: #{info[:strong_params].map { |p| "`#{p}`" }.join(', ')}" if info[:strong_params]&.any?
            lines << ''
          end
          lines.join("\n")
        end
      end
    end
  end
end
