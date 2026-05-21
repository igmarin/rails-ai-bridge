# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class SearchCode
      # Validates search inputs for the SearchCode tool.
      class Validator
        # @param pattern [String] search pattern
        # @param file_type [String, nil] optional file extension filter
        # @param root [String] application root path
        # @param path [String, nil] optional subdirectory path
        def initialize(pattern, file_type, root, path)
          @pattern = pattern
          @file_type = file_type
          @root = root
          @path = path
        end

        # Validates and normalizes all search parameters.
        #
        # @return [Hash, MCP::Tool::Response] normalized params hash on success, error response on failure
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

        # Validates that the pattern does not exceed the maximum byte size.
        #
        # @return [MCP::Tool::Response, nil] error response if too long, nil otherwise
        def validate_pattern_size
          max_b = effective_max_bytes
          return nil if @pattern.to_s.bytesize <= max_b

          pattern_too_long_error(max_b)
        end

        # Returns the effective maximum pattern byte size from configuration.
        #
        # @return [Integer] max bytes (defaults to 2048 if not set or non-positive)
        # :reek:UtilityFunction
        def effective_max_bytes
          max = RailsAiBridge.configuration.search_code_pattern_max_bytes.to_i
          max.positive? ? max : 2048
        end

        # Builds a pattern-too-long error response.
        #
        # @param max_b [Integer] maximum allowed bytes
        # @return [MCP::Tool::Response] error response
        # :reek:UtilityFunction
        def pattern_too_long_error(max_b)
          BaseTool.text_response(
            "Pattern exceeds maximum length (#{max_b} bytes). " \
            'Use a shorter pattern or increase config.search_code_pattern_max_bytes.'
          )
        end

        # Validates and normalizes the file_type parameter.
        #
        # @return [String, MCP::Tool::Response, nil] normalized extension, error response, or nil if absent
        def validate_and_normalize_file_type
          return nil unless present?(@file_type)

          normalized = normalize_extension(@file_type)
          return BaseTool.text_response('Invalid file_type: use only a single safe extension (letters and digits).') unless safe_extension?(normalized)

          allowed = SearchCode.allowed_search_file_types
          return BaseTool.text_response("Invalid file_type: #{@file_type.inspect} is not allowed. Allowed: #{allowed.sort.join(', ')}") unless allowed.include?(normalized)

          normalized
        end

        # Checks whether a value is present (non-nil, non-empty).
        #
        # @param value [Object] value to check
        # @return [Boolean]
        # :reek:UtilityFunction
        def present?(value)
          value && !value.to_s.strip.empty?
        end

        # Normalizes a file extension to lowercase without leading dot.
        #
        # @param value [String] raw extension value
        # @return [String] normalized extension
        # :reek:UtilityFunction
        def normalize_extension(value)
          value.to_s.downcase.strip.delete_prefix('.')
        end

        # Checks whether a normalized extension consists only of safe characters.
        #
        # @param normalized [String] normalized extension string
        # @return [Boolean]
        # :reek:UtilityFunction
        def safe_extension?(normalized)
          normalized.match?(/\A[a-z0-9]+\z/)
        end

        # Validates that the search path is within the application root.
        #
        # @return [String, MCP::Tool::Response] resolved search path or error response
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

        # Builds the full search path by joining root with the optional sub-path.
        #
        # @return [String] absolute search path
        def build_search_path
          @path ? File.join(@root, @path) : @root
        end

        # Checks whether a resolved search path is within the application root (path traversal guard).
        #
        # @param real_search [String] realpath of the search directory
        # @param real_root [String] realpath of the application root
        # @return [Boolean]
        # :reek:UtilityFunction
        def within_root?(real_search, real_root)
          real_search.start_with?(real_root)
        end

        # Returns a path-not-found error response.
        #
        # @return [MCP::Tool::Response] error response
        def path_not_found
          BaseTool.text_response("Path not found: #{@path}")
        end
      end
    end
  end
end
