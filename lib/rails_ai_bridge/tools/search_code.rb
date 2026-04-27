# frozen_string_literal: true

require 'open3'
require 'timeout'

module RailsAiBridge
  module Tools
    # MCP tool searching the app tree with ripgrep (+rg+) or a Ruby fallback.
    #
    # Pattern size is capped by {Configuration#search_code_pattern_max_bytes} (default 2048).
    # Wall-clock limits use {Configuration#search_code_timeout_seconds} (+0+ disables).
    class SearchCode < BaseTool
      tool_name 'rails_search_code'
      description 'Search the Rails codebase for a pattern using ripgrep (rg) or Ruby fallback. Returns
      matching lines with file paths and line numbers. Useful for finding usages, implementations, and patterns.'

      # Hard upper bound for +max_results+ regardless of client input.
      MAX_RESULTS_CAP = 100

      # Fallback when +config.search_code_pattern_max_bytes+ is misconfigured (non-positive).
      DEFAULT_PATTERN_MAX_BYTES = 2048

      # Default extensions when no +file_type+ is given, merged with
      # {RailsAiBridge::Configuration#search_code_allowed_file_types}.
      DEFAULT_ALLOWED_FILE_TYPES = %w[rb erb js ts jsx tsx yml yaml json].freeze

      input_schema(
        properties: {
          pattern: {
            type: 'string',
            description: 'Search pattern (regex supported).'
          },
          path: {
            type: 'string',
            description: "Subdirectory to search in (e.g. 'app/models', 'config'). Default: entire app."
          },
          file_type: {
            type: 'string',
            description: "Filter by allowed file extension (e.g. 'rb', 'js', 'erb'). Default: allowlisted source types only.
            Extra types: config.search_code_allowed_file_types."
          },
          max_results: {
            type: 'integer',
            description: 'Maximum number of results. Default: 30, max: 100.'
          }
        },
        required: ['pattern']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      # @param pattern [String] regex-capable search pattern (required)
      # @param path [String, nil] subdirectory under +Rails.root+ to scope the search
      # @param file_type [String, nil] extension filter (must be allowlisted)
      # @param max_results [Integer] capped at {MAX_RESULTS_CAP}
      # @param server_context [Object, nil] reserved for MCP transport metadata
      # @return [MCP::Tool::Response] search hits as markdown or a validation error response
      def self.call(pattern:, path: nil, file_type: nil, max_results: 30)
        root = Rails.root.to_s

        # Validate inputs
        validation_result = validate_inputs(pattern, file_type)
        return validation_result if validation_result.is_a?(MCP::Tool::Response)

        # Prepare and validate search
        search_params = prepare_search(root, path, max_results, validation_result)
        return search_params if search_params.is_a?(MCP::Tool::Response)

        # Execute search and format response
        execute_and_format_search(pattern, search_params, path)
      end

      private_class_method def self.validate_inputs(pattern, file_type)
        pattern_response = validate_pattern_size(pattern)
        return pattern_response if pattern_response.is_a?(MCP::Tool::Response)

        normalized_type = normalize_and_validate_file_type(file_type)
        return normalized_type if normalized_type.is_a?(MCP::Tool::Response)

        normalized_type
      end

      private_class_method def self.prepare_search(root, path, max_results, normalized_type)
        max_results = normalize_max_results(max_results)
        search_path = prepare_search_path(root, path)
        return search_path if search_path.is_a?(MCP::Tool::Response)

        security_result = validate_path_security(search_path, root, path)
        return security_result if security_result.is_a?(MCP::Tool::Response)

        { search_path: search_path, file_type: normalized_type, max_results: max_results, root: root }
      end

      private_class_method def self.execute_and_format_search(pattern, search_params, path)
        results = execute_search(pattern, search_params[:search_path], search_params[:file_type],
                                 search_params[:max_results], search_params[:root])
        text_response(Formatter.new.call(results, pattern, path))
      end

      private_class_method def self.normalize_max_results(max_results)
        normalized = [max_results.to_i, MAX_RESULTS_CAP].min
        normalized < 1 ? 30 : normalized
      end

      private_class_method def self.prepare_search_path(root, path)
        search_path = path ? File.join(root, path) : root
        return text_response("Path not found: #{path}") unless Dir.exist?(search_path)

        search_path
      end

      private_class_method def self.validate_path_security(search_path, root, path)
        real_search = File.realpath(search_path)
        real_root = File.realpath(root)
        text_response("Path not allowed: #{path}") unless real_search.start_with?(real_root)
      rescue Errno::ENOENT
        text_response("Path not found: #{path}")
      end

      private_class_method def self.execute_search(pattern, search_path, file_type, max_results, root)
        with_search_timeout do
          if ripgrep_available?
            search_with_ripgrep(pattern, search_path, file_type, max_results, root)
          else
            search_with_ruby(pattern, search_path, file_type, max_results, root)
          end
        end
      end

      private_class_method def self.validate_pattern_size(pattern)
        p = pattern.to_s
        max_b = RailsAiBridge.configuration.search_code_pattern_max_bytes.to_i
        max_b = DEFAULT_PATTERN_MAX_BYTES if max_b <= 0

        return nil if p.bytesize <= max_b

        text_response(
          "Pattern exceeds maximum length (#{max_b} bytes). " \
          'Use a shorter pattern or increase config.search_code_pattern_max_bytes.'
        )
      end

      private_class_method def self.with_search_timeout(&)
        sec = RailsAiBridge.configuration.search_code_timeout_seconds.to_f
        return yield if sec <= 0

        Timeout.timeout(sec, &)
      rescue Timeout::Error
        [
          {
            file: 'error',
            line_number: 0,
            content: "Search timed out after #{sec} seconds. Try a narrower path, file_type, or pattern."
          }
        ]
      end

      private_class_method def self.allowed_search_file_types
        extras = RailsAiBridge.configuration.search_code_allowed_file_types.map do |x|
          x.to_s.downcase.strip.delete_prefix('.').gsub(/[^a-z0-9]/, '')
        end.reject(&:empty?)

        (DEFAULT_ALLOWED_FILE_TYPES + extras).uniq
      end

      private_class_method def self.normalize_and_validate_file_type(file_type)
        return nil if file_type.nil? || file_type.to_s.strip.empty?

        normalized = normalize_file_type(file_type)
        return normalized if normalized.is_a?(MCP::Tool::Response)

        validate_file_type_allowed(normalized, file_type)
      end

      private_class_method def self.normalize_file_type(file_type)
        normalized = file_type.to_s.downcase.strip.delete_prefix('.')
        return text_response('Invalid file_type: use only a single safe extension (letters and digits).') unless normalized.match?(/\A[a-z0-9]+\z/)

        normalized
      end

      private_class_method def self.validate_file_type_allowed(normalized, original)
        unless allowed_search_file_types.include?(normalized)
          allowed = allowed_search_file_types.sort.join(', ')
          return text_response("Invalid file_type: #{original.inspect} is not allowed. Allowed: #{allowed}")
        end
        normalized
      end

      private_class_method def self.append_ripgrep_secret_excludes(cmd)
        %w[key pem p12 pfx crt].each { |ext| cmd << '--glob' << "!*.#{ext}" }
        cmd << '--glob' << '!.env'
        cmd << '--glob' << '!.env.*'
      end

      private_class_method def self.ripgrep_available?
        @ripgrep_available ||= system('which rg > /dev/null 2>&1')
      end

      private_class_method def self.search_with_ripgrep(pattern, search_path, file_type, max_results, root)
        cmd = build_ripgrep_command(pattern, search_path, file_type, max_results)

        output, _status = Open3.capture2(*cmd, err: File::NULL)
        parse_rg_output(output, root)
      rescue StandardError => error
        [{ file: 'error', line_number: 0, content: error.message }]
      end

      private_class_method def self.build_ripgrep_command(pattern, search_path, file_type, max_results)
        cmd = ['rg', '--no-heading', '--line-number', '--max-count', max_results.to_s]

        add_excluded_paths_to_command(cmd)
        append_ripgrep_secret_excludes(cmd)
        add_file_type_filters_to_command(cmd, file_type)

        cmd << pattern
        cmd << search_path
        cmd
      end

      private_class_method def self.add_excluded_paths_to_command(cmd)
        RailsAiBridge.configuration.excluded_paths.each do |p|
          cmd << "--glob=!#{p}"
        end
      end

      private_class_method def self.add_file_type_filters_to_command(cmd, file_type)
        if file_type
          cmd.push('--type-add', "custom:*.#{file_type}", '--type', 'custom')
        else
          allowed_search_file_types.each do |ext|
            cmd << '--glob' << "*.#{ext}"
          end
        end
      end

      private_class_method def self.ruby_glob_for(search_path, file_type)
        if file_type
          File.join(search_path, '**', "*.#{file_type}")
        else
          exts = allowed_search_file_types.uniq.join(',')
          File.join(search_path, '**', "*.{#{exts}}")
        end
      end

      private_class_method def self.skip_secret_file?(_relative, basename)
        bn = basename.to_s
        return true if bn.match?(/\A\.env/i)
        return true if bn.end_with?('.key', '.pem', '.p12', '.pfx', '.crt')

        false
      end

      private_class_method def self.search_with_ruby(pattern, search_path, file_type, max_results, root)
        results = []
        regex = Regexp.new(pattern, Regexp::IGNORECASE)
        glob = ruby_glob_for(search_path, file_type)
        excluded = RailsAiBridge.configuration.excluded_paths

        Dir.glob(glob).each do |file|
          results = process_file_for_search(file, root, regex, excluded, max_results, results)
          return results if results.size >= max_results
        rescue StandardError => _error
          next # Skip binary/unreadable files
        end

        results
      rescue RegexpError => error
        [{ file: 'error', line_number: 0, content: "Invalid pattern: #{error.message}" }]
      end

      private_class_method def self.process_file_for_search(file, root, regex, excluded, max_results, results)
        relative = file.sub("#{root}/", '')
        return results if should_skip_file?(relative, file, excluded)

        File.readlines(file).each_with_index do |line, idx|
          if line.match?(regex)
            results << { file: relative, line_number: idx + 1, content: line }
            return results if results.size >= max_results
          end
        end
        results
      end

      private_class_method def self.should_skip_file?(relative, file, excluded)
        return true if excluded.any? { |ex| relative.start_with?(ex) }
        return true if skip_secret_file?(relative, File.basename(file))

        false
      end

      private_class_method def self.parse_rg_output(output, root)
        output.lines.filter_map do |line|
          match = line.match(/^(.+?):(\d+):(.*)$/)
          next unless match

          {
            file: match[1].sub("#{root}/", ''),
            line_number: match[2].to_i,
            content: match[3]
          }
        end
      end
    end
  end
end
