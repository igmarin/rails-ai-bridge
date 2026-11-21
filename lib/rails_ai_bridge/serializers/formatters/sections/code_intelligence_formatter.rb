# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Code Intelligence section: local index availability and
      # staleness for CodeGraph and Graphify.
      #
      # @see Formatters::Sections::SectionFormatter
      class CodeIntelligenceFormatter < SectionFormatter
        section :code_intelligence

        private

        def render(data)
          codegraph = data[:codegraph]
          graphify = data[:graphify]

          lines = ['## Code Intelligence Indexes']
          lines.concat(codegraph_lines(codegraph))
          lines.concat(graphify_lines(graphify))
          lines.join("\n")
        end

        # @param info [Hash, nil]
        # @return [Array<String>]
        def codegraph_lines(info)
          return ['- CodeGraph: not present (`codegraph index` to generate)'] unless info&.[](:present)

          [
            "- CodeGraph: `#{info[:index_path]}`",
            "  - indexed_at: #{format_time(info[:indexed_at])}"
          ]
        end

        # @param info [Hash, nil]
        # @return [Array<String>]
        def graphify_lines(info)
          return ['- Graphify: not present (`graphify extract .` to generate)'] unless info&.[](:present)

          commit = info[:graph_commit]
          lines = [
            "- Graphify: `#{info[:graph_path]}`",
            "  - generated_at: #{format_time(info[:generated_at])}"
          ]
          lines << "  - built from commit: `#{commit}`" if commit
          lines << "  - staleness: #{staleness_label(info[:stale])}"
          lines
        end

        # @param stale [Boolean, nil]
        # @return [String]
        def staleness_label(stale)
          case stale
          when true then 'stale (graph predates current HEAD)'
          when false then 'current'
          else 'unknown (missing commit info)'
          end
        end

        # @param time [Time, nil]
        # @return [String]
        def format_time(time)
          time ? time.strftime('%Y-%m-%d %H:%M:%S %Z') : 'unknown'
        end
      end
    end
  end
end
