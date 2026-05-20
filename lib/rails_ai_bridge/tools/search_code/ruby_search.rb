# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class SearchCode
      # Executes codebase searches using Ruby fallback.
      # Executes codebase searches using Ruby fallback.
      class RubySearch
        # Encapsulates file-level search logic.
        class FileProcessor
          def initialize(regex, results, max_results, root)
            @regex = regex
            @results = results
            @max_results = max_results
            @root = root
          end

          def process(file)
            return if skip_file?(file)

            relative = file.sub("#{@root}/", '')
            File.readlines(file).each_with_index do |line, idx|
              next unless line.match?(@regex)

              @results << { file: relative, line_number: idx + 1, content: line }
              return :full if @results.size >= @max_results
            end
          end

          private

          def skip_file?(file)
            relative = file.sub("#{@root}/", '')
            excluded = RailsAiBridge.configuration.excluded_paths
            return true if excluded.any? { |ex| relative.start_with?(ex) }

            basename = File.basename(file)
            basename.match?(/\A\.env/i) || basename.end_with?('.key', '.pem', '.p12', '.pfx', '.crt')
          end
        end

        def initialize(search_params)
          @pattern = search_params[:pattern]
          @search_path = search_params[:search_path]
          @file_type = search_params[:file_type]
          @max_results = search_params[:max_results]
          @root = search_params[:root]
        end

        def call
          results = []
          regex = Regexp.new(@pattern, Regexp::IGNORECASE)
          processor = FileProcessor.new(regex, results, @max_results, @root)

          Dir.glob(ruby_glob).each do |file|
            break if processor.process(file) == :full
          rescue StandardError
            next
          end
          results
        rescue RegexpError => error
          [{ file: 'error', line_number: 0, content: "Invalid pattern: #{error.message}" }]
        end

        private

        def ruby_glob
          exts = @file_type || SearchCode.allowed_search_file_types.uniq.join(',')
          File.join(@search_path, '**', "*.{#{exts}}")
        end
      end
    end
  end
end
