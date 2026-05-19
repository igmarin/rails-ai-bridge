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
          max_b = RailsAiBridge.configuration.search_code_pattern_max_bytes.to_i
          max_b = 2048 if max_b <= 0
          return nil if @pattern.to_s.bytesize <= max_b

          BaseTool.text_response(
            "Pattern exceeds maximum length (#{max_b} bytes). " \
            'Use a shorter pattern or increase config.search_code_pattern_max_bytes.'
          )
        end

        def validate_and_normalize_file_type
          return nil if @file_type.nil? || @file_type.to_s.strip.empty?

          normalized = @file_type.to_s.downcase.strip.delete_prefix('.')
          return BaseTool.text_response('Invalid file_type: use only a single safe extension (letters and digits).') unless normalized.match?(/\A[a-z0-9]+\z/)

          allowed = SearchCode.allowed_search_file_types
          return BaseTool.text_response("Invalid file_type: #{@file_type.inspect} is not allowed. Allowed: #{allowed.sort.join(', ')}") unless allowed.include?(normalized)

          normalized
        end

        def validate_path_security
          search_path = @path ? File.join(@root, @path) : @root
          return BaseTool.text_response("Path not found: #{@path}") unless Dir.exist?(search_path)

          real_search = File.realpath(search_path)
          real_root = File.realpath(@root)
          return BaseTool.text_response("Path not allowed: #{@path}") unless real_search.start_with?(real_root)

          search_path
        rescue Errno::ENOENT
          BaseTool.text_response("Path not found: #{@path}")
        end
      end
    end
  end
end
