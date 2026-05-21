# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class SearchCode
      # Validates search inputs for the SearchCode tool.
      class Validator
        def initialize(pattern, file_type, root, path)
          @pattern = pattern
          @file_type = file_type
          @root = root
          @path = path
        end

        def validate
          pattern_error = validate_pattern_size
          return pattern_error if pattern_error

          type = validate_and_normalize_file_type
          return type if type.is_a?(MCP::Tool::Response)

          security = validate_path_security
          return security if security.is_a?(MCP::Tool::Response)

          { file_type: type, search_path: security }
        end

        private

        def validate_pattern_size
          max_b = effective_max_bytes
          return nil if @pattern.to_s.bytesize <= max_b

          pattern_too_long_error(max_b)
        end

        # :reek:UtilityFunction
        def effective_max_bytes
          max = RailsAiBridge.configuration.search_code_pattern_max_bytes.to_i
          max.positive? ? max : 2048
        end

        # :reek:UtilityFunction
        def pattern_too_long_error(max_b)
          BaseTool.text_response(
            "Pattern exceeds maximum length (#{max_b} bytes). " \
            'Use a shorter pattern or increase config.search_code_pattern_max_bytes.'
          )
        end

        def validate_and_normalize_file_type
          return nil unless present?(@file_type)

          normalized = normalize_extension(@file_type)
          return BaseTool.text_response('Invalid file_type: use only a single safe extension (letters and digits).') unless safe_extension?(normalized)

          allowed = SearchCode.allowed_search_file_types
          return BaseTool.text_response("Invalid file_type: #{@file_type.inspect} is not allowed. Allowed: #{allowed.sort.join(', ')}") unless allowed.include?(normalized)

          normalized
        end

        # :reek:UtilityFunction
        def present?(value)
          value && !value.to_s.strip.empty?
        end

        # :reek:UtilityFunction
        def normalize_extension(value)
          value.to_s.downcase.strip.delete_prefix('.')
        end

        # :reek:UtilityFunction
        def safe_extension?(normalized)
          normalized.match?(/\A[a-z0-9]+\z/)
        end

        def validate_path_security
          search_path = build_search_path
          return path_not_found unless Dir.exist?(search_path)

          real_search = File.realpath(search_path)
          real_root = File.realpath(@root)
          return BaseTool.text_response("Path not allowed: #{@path}") unless within_root?(real_search, real_root)

          search_path
        rescue Errno::ENOENT
          path_not_found
        end

        def build_search_path
          @path ? File.join(@root, @path) : @root
        end

        # :reek:UtilityFunction
        def within_root?(real_search, real_root)
          real_search.start_with?(real_root)
        end

        def path_not_found
          BaseTool.text_response("Path not found: #{@path}")
        end
      end
    end
  end
end
