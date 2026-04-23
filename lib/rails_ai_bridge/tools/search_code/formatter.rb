# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class SearchCode
      # Formats the search results into a markdown string.
      class Formatter
        # @param results [Array<Hash>] Array of search results.
        # @param pattern [String] The search pattern used.
        # @param path [String, nil] The path searched within.
        # @return [String] The formatted markdown output.
        def call(results, pattern, path)
          if results.empty?
            return "No results found for '#{pattern}'#{" in #{path}" if path}."
          end

          output = results.map { |r| "#{r[:file]}:#{r[:line_number]}: #{r[:content].strip}" }.join("\n")
          header = "# Search: `#{pattern}`
**#{results.size} results**#{" in #{path}" if path}

```
"
          footer = "
```"

          "#{header}#{output}#{footer}"
        end
      end
    end
  end
end
