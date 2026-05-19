# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Semantic Analysis section from rubydex data.
      #
      # @see Formatters::Providers::SectionFormatter
      class SemanticFormatter < SectionFormatter
        section :semantic

        private

        def render(data)
          return if data[:info] || data[:error] || data.empty?

          lines = []

          render_codebase_stats(lines, data[:codebase_stats])
          render_patterns(lines, data[:patterns])
          render_relationships(lines, data[:relationships])
          render_complexity_hotspots(lines, data[:complexity_hotspots])

          return if lines.empty?

          lines.unshift('## Semantic Analysis (rubydex)')
          lines.join("\n")
        end

        def render_codebase_stats(lines, stats)
          return unless stats.is_a?(Hash) && stats.any?

          lines << ''
          lines << '### Codebase Statistics'
          lines << "- Files indexed: #{stats[:total_files]}"
          lines << "- Total declarations: #{stats[:total_declarations]}"
          lines << "- Classes: #{stats[:total_classes]}"
          lines << "- Modules: #{stats[:total_modules]}"
          lines << "- Methods: #{stats[:total_methods]}"
          lines << "- Constant references: #{stats[:total_constant_references]}"
          lines << "- Method references: #{stats[:total_method_references]}"
        end

        def render_patterns(lines, patterns)
          return unless patterns.is_a?(Hash) && patterns.any?

          sublines = []
          common = patterns[:common_patterns]
          sublines << "- Common patterns: #{common.join(', ')}" if common.is_a?(Array) && common.any?

          ns = patterns[:namespace_distribution]
          if ns.is_a?(Hash) && ns.any?
            sublines << '- Namespace distribution:'
            ns.each { |name, count| sublines << "  - `#{name}`: #{count} declarations" }
          end

          if sublines.any?
            lines << ''
            lines << '### Detected Patterns'
            lines.concat(sublines)
          end
        end

        def render_relationships(lines, relationships)
          return unless relationships.is_a?(Hash) && relationships.any?

          sublines = []
          tree = relationships[:inheritance_tree]
          if tree.is_a?(Hash) && tree.any?
            sublines << '- Inheritance tree (top parents):'
            tree.first(10).each do |parent, children|
              sublines << "  - `#{parent}` → #{children.join(', ')}"
            end
          end

          extended = relationships[:most_extended]
          if extended.is_a?(Array) && extended.any?
            sublines << '- Most extended classes:'
            extended.first(5).each do |entry|
              sublines << "  - `#{entry[:name]}` (#{entry[:descendants_count]} descendants)"
            end
          end

          orphans = relationships[:orphan_classes]
          sublines << "- Leaf classes (no descendants): #{orphans}" if orphans.is_a?(Integer) && orphans.positive?

          if sublines.any?
            lines << ''
            lines << '### Code Relationships'
            lines.concat(sublines)
          end
        end

        def render_complexity_hotspots(lines, hotspots)
          return unless hotspots.is_a?(Array) && hotspots.any?

          lines << ''
          lines << '### Complexity Hotspots'
          lines << 'Areas with the highest structural complexity (definitions × depth × reach):'
          hotspots.first(10).each do |h|
            lines << "- `#{h[:name]}` [#{h[:type]}] — score: #{h[:complexity_score]} " \
                     "(#{h[:definitions_count]} defs, #{h[:ancestors_count]} ancestors, #{h[:descendants_count]} descendants)"
          end
        end
      end
    end
  end
end
