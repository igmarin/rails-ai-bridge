# frozen_string_literal: true

require 'open3'
require 'timeout'

module RailsAiBridge
  module Tools
    # MCP tool searching the app tree with ripgrep (+rg+) or a Ruby fallback.
    #
    # Pattern size is capped by {RailsAiBridge::Configuration#search_code_pattern_max_bytes} (default 2048).
    # Wall-clock limits use {RailsAiBridge::Configuration#search_code_timeout_seconds} (+0+ disables).
    class SearchCode < BaseTool
      tool_name 'rails_search_code'
      description 'Search the Rails codebase for a pattern using ripgrep (rg) or Ruby fallback. Returns
      matching lines with file paths and line numbers. Useful for finding usages, implementations, and patterns.'

      # Hard upper bound for +max_results+ regardless of client input.
      MAX_RESULTS_CAP = 100

      # Default extensions when no +file_type+ is given, merged with
      # {RailsAiBridge::Configuration#search_code_allowed_file_types}.
      DEFAULT_ALLOWED_FILE_TYPES = %w[rb erb js ts jsx tsx yml yaml json].freeze

      input_schema(
        properties: {
          pattern: { type: 'string', description: 'Search pattern (regex supported).' },
          path: { type: 'string', description: 'Subdirectory to search in.' },
          file_type: { type: 'string', description: 'Filter by allowed file extension.' },
          max_results: { type: 'integer', description: 'Maximum number of results.' }
        },
        required: ['pattern']
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(pattern:, path: nil, file_type: nil, max_results: 30)
        root = Rails.root.to_s
        validator = Validator.new(pattern, file_type, root, path)
        validated = validator.validate
        return validated if validated.is_a?(MCP::Tool::Response)

        max_res = normalize_max_results(max_results)
        search_params = validated.merge(pattern: pattern, max_results: max_res, root: root)

        results = with_search_timeout do
          search_engine(search_params)
        end

        text_response(Formatter.new.call(results, pattern, path))
      end

      def self.allowed_search_file_types
        extras = RailsAiBridge.configuration.search_code_allowed_file_types.map do |x|
          x.to_s.downcase.strip.delete_prefix('.').gsub(/[^a-z0-9]/, '')
        end.reject(&:empty?)

        (DEFAULT_ALLOWED_FILE_TYPES + extras).uniq
      end

      def self.normalize_max_results(max_results)
        normalized = [max_results.to_i, MAX_RESULTS_CAP].min
        normalized < 1 ? 30 : normalized
      end

      def self.search_engine(search_params)
        if ripgrep_available?
          RipgrepSearch.new(search_params).call
        else
          RubySearch.new(search_params).call
        end
      end

      def self.ripgrep_available?
        return @ripgrep_available if instance_variable_defined?(:@ripgrep_available)

        @ripgrep_available = Open3.capture2('rg', '--version').last.success?
      end

      def self.with_search_timeout(&)
        sec = RailsAiBridge.configuration.search_code_timeout_seconds.to_f
        return yield if sec <= 0

        Timeout.timeout(sec, &)
      rescue Timeout::Error
        [{ file: 'error', line_number: 0, content: "Search timed out after #{sec} seconds." }]
      end
    end
  end
end
