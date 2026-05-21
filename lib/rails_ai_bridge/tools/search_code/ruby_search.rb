# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class SearchCode
      # Executes codebase searches using Ruby fallback.
      class RubySearch
        # Value object wrapping validated search parameters.
        SearchParams = Struct.new(:pattern, :search_path, :file_type, :max_results, :root, keyword_init: true)

        # Encapsulates file-level search logic.
        class FileProcessor
          SECRET_EXTENSIONS = %w[.key .pem .p12 .pfx .crt].freeze

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

            secret_file?(File.basename(file))
          end

          def secret_file?(basename)
            return true if basename.match?(/\A\.env/i)

            SECRET_EXTENSIONS.any? { |ext| basename.end_with?(ext) }
          end
        end

        def initialize(search_params)
          @params = SearchParams.new(**search_params.slice(:pattern, :search_path, :file_type, :max_results, :root))
        end

        def call
          results = []
          regex = Regexp.new(@params.pattern, Regexp::IGNORECASE)
          processor = FileProcessor.new(regex, results, @params.max_results, @params.root)

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
          exts = @params.file_type || SearchCode.allowed_search_file_types.uniq.join(',')
          File.join(@params.search_path, '**', "*.{#{exts}}")
        end
      end
    end
  end
end
