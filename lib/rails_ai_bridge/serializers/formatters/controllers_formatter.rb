# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Controllers section with actions, filters, and strong params.
      class ControllersFormatter < Base
        # @return [String, nil]
        def call
          data = context[:controllers]
          return unless data
          return if data[:error]

          controllers = data[:controllers] || {}
          return if controllers.empty?

          lines = [ "## Controllers (#{controllers.size})" ]
          controllers.each do |name, info|
            next if info[:error]
            lines << "### #{name}"
            lines << "- Parent: `#{info[:parent_class]}`" if info[:parent_class]
            lines << "- API controller: yes" if info[:api_controller]
            lines << "- Actions: #{info[:actions]&.join(', ')}" if info[:actions]&.any?
            if info[:filters]&.any?
              lines << "- Filters: #{info[:filters].map { |f| "#{f[:kind]} #{f[:name]}" }.join(', ')}"
            end
            lines << "- Strong params: #{info[:strong_params].join(', ')}" if info[:strong_params]&.any?
          end
          lines.join("\n")
        end
      end
    end
  end
end
