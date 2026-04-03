# frozen_string_literal: true

require "open3"

module RailsAiBridge
  module Tools
    # MCP tool searching the app tree with ripgrep (+rg+) or a Ruby fallback.
    class SearchCode < BaseTool
      tool_name "rails_search_code"
      description "Search the Rails codebase for a pattern using ripgrep (rg) or Ruby fallback. Returns matching lines with file paths and line numbers. Useful for finding usages, implementations, and patterns."

      # Hard upper bound for +max_results+ regardless of client input.
      MAX_RESULTS_CAP = 100

      # Default extensions when no +file_type+ is given, merged with
      # {RailsAiBridge::Configuration#search_code_allowed_file_types}.
      DEFAULT_ALLOWED_FILE_TYPES = %w[rb erb js ts jsx tsx yml yaml json].freeze

      input_schema(
        properties: {
          pattern: {
            type: "string",
            description: "Search pattern (regex supported)."
          },
          path: {
            type: "string",
            description: "Subdirectory to search in (e.g. 'app/models', 'config'). Default: entire app."
          },
          file_type: {
            type: "string",
            description: "Filter by allowed file extension (e.g. 'rb', 'js', 'erb'). Default: allowlisted source types only. Extra types: config.search_code_allowed_file_types."
          },
          max_results: {
            type: "integer",
            description: "Maximum number of results. Default: 30, max: 100."
          }
        },
        required: [ "pattern" ]
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param pattern [String] regex-capable search pattern (required)
      # @param path [String, nil] subdirectory under +Rails.root+ to scope the search
      # @param file_type [String, nil] extension filter (must be allowlisted)
      # @param max_results [Integer] capped at {MAX_RESULTS_CAP}
      # @param server_context [Object, nil] reserved for MCP transport metadata
      # @return [MCP::Tool::Response] search hits as markdown or a validation error response
      def self.call(pattern:, path: nil, file_type: nil, max_results: 30, server_context: nil)
        root = Rails.root.to_s

        normalized_type = normalize_and_validate_file_type(file_type)
        return normalized_type if normalized_type.is_a?(MCP::Tool::Response)

        file_type = normalized_type

        # Cap max_results
        max_results = [ max_results.to_i, MAX_RESULTS_CAP ].min
        max_results = 30 if max_results < 1

        search_path = path ? File.join(root, path) : root

        # Path traversal protection
        unless Dir.exist?(search_path)
          return text_response("Path not found: #{path}")
        end

        begin
          real_search = File.realpath(search_path)
          real_root = File.realpath(root)
          unless real_search.start_with?(real_root)
            return text_response("Path not allowed: #{path}")
          end
        rescue Errno::ENOENT
          return text_response("Path not found: #{path}")
        end

        results = if ripgrep_available?
                    search_with_ripgrep(pattern, search_path, file_type, max_results, root)
        else
                    search_with_ruby(pattern, search_path, file_type, max_results, root)
        end

        # Use the Formatter to generate the output
        text_response(Formatter.new.call(results, pattern, path))
      end

      private_class_method def self.allowed_search_file_types
        extras = RailsAiBridge.configuration.search_code_allowed_file_types.map do |x|
          x.to_s.downcase.strip.delete_prefix(".").gsub(/[^a-z0-9]/, "")
        end.reject(&:empty?)

        (DEFAULT_ALLOWED_FILE_TYPES + extras).uniq
      end

      private_class_method def self.normalize_and_validate_file_type(file_type)
        return nil if file_type.nil? || file_type.to_s.strip.empty?

        normalized = file_type.to_s.downcase.strip.delete_prefix(".")
        unless normalized.match?(/\A[a-z0-9]+\z/)
          return text_response("Invalid file_type: use only a single safe extension (letters and digits).")
        end

        unless allowed_search_file_types.include?(normalized)
          allowed = allowed_search_file_types.sort.join(", ")
          return text_response("Invalid file_type: #{file_type.inspect} is not allowed. Allowed: #{allowed}")
        end

        normalized
      end

      private_class_method def self.append_ripgrep_secret_excludes(cmd)
        %w[key pem p12 pfx crt].each { |ext| cmd << "--glob" << "!*.#{ext}" }
        cmd << "--glob" << "!.env"
        cmd << "--glob" << "!.env.*"
      end

      private_class_method def self.ripgrep_available?
        @rg_available ||= system("which rg > /dev/null 2>&1")
      end

      private_class_method def self.search_with_ripgrep(pattern, search_path, file_type, max_results, root)
        cmd = [ "rg", "--no-heading", "--line-number", "--max-count", max_results.to_s ]

        RailsAiBridge.configuration.excluded_paths.each do |p|
          cmd << "--glob=!#{p}"
        end

        append_ripgrep_secret_excludes(cmd)

        if file_type
          cmd.push("--type-add", "custom:*.#{file_type}", "--type", "custom")
        else
          allowed_search_file_types.each do |ext|
            cmd << "--glob" << "*.#{ext}"
          end
        end

        cmd << pattern
        cmd << search_path

        output, _status = Open3.capture2(*cmd, err: File::NULL)
        parse_rg_output(output, root)
      rescue => e
        [ { file: "error", line_number: 0, content: e.message } ]
      end

      private_class_method def self.ruby_glob_for(search_path, file_type)
        if file_type
          File.join(search_path, "**", "*.#{file_type}")
        else
          exts = allowed_search_file_types.uniq.join(",")
          File.join(search_path, "**", "*.{#{exts}}")
        end
      end

      private_class_method def self.skip_secret_file?(relative, basename)
        bn = basename.to_s
        return true if bn.match?(/\A\.env/i)
        return true if bn.end_with?(".key", ".pem", ".p12", ".pfx", ".crt")

        false
      end

      private_class_method def self.search_with_ruby(pattern, search_path, file_type, max_results, root)
        results = []
        regex = Regexp.new(pattern, Regexp::IGNORECASE)
        glob = ruby_glob_for(search_path, file_type)
        excluded = RailsAiBridge.configuration.excluded_paths

        Dir.glob(glob).each do |file|
          relative = file.sub("#{root}/", "")
          next if excluded.any? { |ex| relative.start_with?(ex) }
          next if skip_secret_file?(relative, File.basename(file))

          File.readlines(file).each_with_index do |line, idx|
            if line.match?(regex)
              results << { file: relative, line_number: idx + 1, content: line }
              return results if results.size >= max_results
            end
          end
        rescue => _e
          next # Skip binary/unreadable files
        end

        results
      rescue RegexpError => e
        [ { file: "error", line_number: 0, content: "Invalid pattern: #{e.message}" } ]
      end

      private_class_method def self.parse_rg_output(output, root)
        output.lines.filter_map do |line|
          match = line.match(/^(.+?):(\d+):(.*)$/)
          next unless match

          {
            file: match[1].sub("#{root}/", ""),
            line_number: match[2].to_i,
            content: match[3]
          }
        end
      end
    end
  end
end
