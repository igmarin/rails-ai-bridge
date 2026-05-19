# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class SearchCode
      # Executes codebase searches using Ruby fallback.
      class RubySearch
        def initialize(pattern, search_path, file_type, max_results, root)
          @pattern = pattern
          @search_path = search_path
          @file_type = file_type
          @max_results = max_results
          @root = root
          @excluded = RailsAiBridge.configuration.excluded_paths
        end

        def call
          results = []
          regex = Regexp.new(@pattern, Regexp::IGNORECASE)
          Dir.glob(ruby_glob).each do |file|
            process_file(file, regex, results)
            return results if results.size >= @max_results
          rescue StandardError
            next
          end
          results
        rescue RegexpError => e
          [{ file: 'error', line_number: 0, content: "Invalid pattern: #{e.message}" }]
        end

        private

        def ruby_glob
          exts = @file_type ? @file_type : SearchCode.allowed_search_file_types.uniq.join(',')
          File.join(@search_path, '**', "*.{#{exts}}")
        end

        def process_file(file, regex, results)
          relative = file.sub("#{@root}/", '')
          return if should_skip_file?(relative, file)

          File.readlines(file).each_with_index do |line, idx|
            if line.match?(regex)
              results << { file: relative, line_number: idx + 1, content: line }
              return if results.size >= @max_results
            end
          end
        end

        def should_skip_file?(relative, file)
          return true if @excluded.any? { |ex| relative.start_with?(ex) }

          bn = File.basename(file)
          return true if bn.match?(/\A\.env/i)
          return true if bn.end_with?('.key', '.pem', '.p12', '.pfx', '.crt')

          false
        end
      end
    end
  end
end
