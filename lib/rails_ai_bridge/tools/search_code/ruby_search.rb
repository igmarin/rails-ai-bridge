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

          # @param regex [Regexp] compiled search pattern
          # @param results [Array<Hash>] shared result accumulator
          # @param max_results [Integer] maximum number of results
          # @param root [String] application root path
          def initialize(regex, results, max_results, root)
            @regex = regex
            @results = results
            @max_results = max_results
            @root = root
          end

          # Processes a single file, collecting matching lines into results.
          #
          # @param file [String] absolute path to the file
          # @return [:full, nil] +:full+ when the result limit is hit, nil otherwise
          def process(file)
            return if skip_file?(file)

            relative = file.sub("#{@root}/", '')
            File.readlines(file).each_with_index do |line, idx|
              next unless line.match?(@regex)

              @results << { file: relative, line_number: idx + 1, content: line }
              return :full if @results.size >= @max_results
            end
          end

          # Checks if a filename matches secret file patterns (case-insensitive .env and common key extensions).
          #
          # `@param` basename [String] file basename
          # `@return` [Boolean] +true+ if the file looks like a secret file
          def self.secret_file?(basename)
            normalized = basename.downcase
            return true if normalized.start_with?('.env')

            SECRET_EXTENSIONS.any? { |ext| normalized.end_with?(ext) }
          end

          private

          # Determines whether a file should be skipped (excluded path or secret file).
          #
          # @param file [String] absolute path to the file
          # @return [Boolean] +true+ if the file should be skipped
          def skip_file?(file)
            relative = file.sub("#{@root}/", '')
            excluded = RailsAiBridge.configuration.excluded_paths
            return true if excluded.any? { |ex| relative.start_with?(ex) }

            self.class.secret_file?(File.basename(file))
          end
        end

        # @param search_params [Hash] validated search parameters (+:pattern+, +:search_path+, +:file_type+, +:max_results+, +:root+)
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

        # Builds a glob pattern for the file types to search.
        #
        # @return [String] glob pattern string
        def ruby_glob
          exts = @params.file_type || SearchCode.allowed_search_file_types.uniq.join(',')
          File.join(@params.search_path, '**', "*.{#{exts}}")
        end
      end
    end
  end
end
