# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool for semantic code search using rubydex.
    #
    # Searches declarations (classes, modules, methods, constants) by name
    # using rubydex's semantic index. Unlike +rails_search_code+ which greps
    # file contents, this tool understands Ruby code structure and returns
    # semantically meaningful results with declaration types and locations.
    #
    # Requires rubydex to be installed and enabled in configuration.
    class SearchSemantic < BaseTool
      tool_name 'rails_search_semantic'
      description 'Semantic search for Ruby declarations (classes, modules, methods, constants) ' \
                  'using rubydex static analysis. Returns structured results with types, locations, ' \
                  'and relationships. Requires rubydex to be installed and enabled.'

      # Hard upper bound for +max_results+ regardless of client input.
      MAX_RESULTS_CAP = 50

      input_schema(
        properties: {
          query: {
            type: 'string',
            description: 'Search query for declarations (e.g. "User", "Foo::Bar", "User#save").'
          },
          path: {
            type: 'string',
            description: 'Filter results to declarations in a specific file path (relative to Rails root).'
          },
          max_results: {
            type: 'integer',
            description: 'Maximum number of results. Default: 20, max: 50.'
          }
        },
        required: ['query']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param query [String] declaration name search query (required)
      # @param path [String, nil] optional file path filter
      # @param max_results [Integer] capped at {MAX_RESULTS_CAP}
      # @return [MCP::Tool::Response]
      def self.call(query:, path: nil, max_results: 20)
        unless rubydex_available?
          return text_response('Rubydex is not available. Install the rubydex gem and set ' \
                               'config.rubydex_enabled = true to enable semantic search.')
        end

        max_results = normalize_max_results(max_results)

        if path
          results = adapter.file_declarations(path)
          results = results.select { |result| result[:name].to_s.downcase.include?(query.downcase) }
        else
          results = adapter.search(query, max_results: max_results)
        end

        results = results.first(max_results)
        text_response(format_results(results, query, path))
      end

      private_class_method def self.rubydex_available?
        config.rubydex_available?
      end

      private_class_method def self.adapter
        RubydexAdapter.instance
      end

      private_class_method def self.normalize_max_results(max_results)
        normalized = [max_results.to_i, MAX_RESULTS_CAP].min
        normalized < 1 ? 20 : normalized
      end

      private_class_method def self.format_results(results, query, path)
        return "No declarations found matching '#{query}'#{" in #{path}" if path}." if results.empty?

        lines = ["## Semantic Search Results for '#{query}'#{" in #{path}" if path}", '']
        lines << "Found #{results.size} declaration(s):"
        lines << ''

        results.each do |result|
          type_badge = result[:type] ? "[#{result[:type]}]" : ''
          name = result[:name] || 'unknown'
          lines << "### #{name} #{type_badge}"
          lines << "- **Location:** `#{result[:location]}`" if result[:location]
          lines << "- **Owner:** `#{result[:owner]}`" if result[:owner]

          lines << "- **Ancestors:** #{result[:ancestors].join(', ')}" if result[:ancestors]&.any?

          lines << "- **Descendants:** #{result[:descendants].join(', ')}" if result[:descendants]&.any?

          if result[:definitions]&.any?
            lines << '- **Definitions:**'
            result[:definitions].each do |defn|
              loc = defn[:location] ? " (`#{defn[:location]}`)" : ''
              lines << "  - `#{defn[:name]}`#{loc}"
            end
          end

          lines << ''
        end

        lines.join("\n")
      end
    end
  end
end
