# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetView
      # Formats full view details including templates, partials, helpers, and components.
      class FullFormatter < BaseFormatter
        # @return [String] The formatted full output.
        def call
          @filtered = filter_view_data
          return "View introspection failed: #{@filtered[:error]}" if @filtered[:error]

          lines = [StandardFormatter.new(context: @context, controller: @controller, partial: @partial).call]
          lines.concat(helper_lines)
          lines.concat(component_lines)
          footer = tags.footer(fact_provenances)
          lines << '' << footer if footer
          lines.join("\n")
        end

        private

        def tags
          @tags ||= ProvenanceLines.new(RailsAiBridge.configuration.confidence_tags_enabled)
        end

        def section_provenance(section)
          @context.dig(:provenance, section)
        end

        def helper_lines
          helpers = @filtered[:helpers]
          return [] if helpers.empty?

          helpers.each_with_object(['', '## Helpers']) do |helper, lines|
            methods = Array(helper[:methods]).join(', ')
            lines << tags.tag("- `#{helper[:file]}`: #{methods}", section_provenance(:helpers))
          end
        end

        # :reek:FeatureEnvy -- formats the component list from the filtered payload; no other state is involved
        def component_lines
          components = @filtered[:view_components]
          return [] if components.empty?

          ['', '## View Components', *components.map { |component| "- `#{component}`" }]
        end

        # One provenance per rendered fact, so the footer tallies what the full view shows.
        def fact_provenances
          counts = {
            layouts: @filtered[:layouts].size,
            templates: @filtered[:templates].values.sum(&:size),
            partials: @filtered[:shared_partials].size + @filtered[:controller_partials].values.sum(&:size),
            helpers: @filtered[:helpers].sum { |helper| Array(helper[:methods]).size },
            view_components: @filtered[:view_components].size,
            template_engines: @filtered[:template_engines].size
          }
          counts.flat_map { |section, count| Array.new(count, section_provenance(section)) }
        end
      end
    end
  end
end
