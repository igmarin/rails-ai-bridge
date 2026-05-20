# frozen_string_literal: true

require 'open3'

module RailsAiBridge
  module Tools
    class SearchCode
      # Executes codebase searches using ripgrep.
      class RipgrepSearch
        def initialize(params)
          @params = params
          @root = params[:root]
        end

        def call
          cmd = CommandBuilder.new(@params).build
          output, _status = Open3.capture2(*cmd, err: File::NULL)
          parse_output(output)
        rescue StandardError => error
          [{ file: 'error', line_number: 0, content: error.message }]
        end

        private

        def parse_output(output)
          output.lines.filter_map { |line| parse_line(line) }
        end

        def parse_line(line)
          match = line.match(/^(.+?):(\d+):(.*)$/)
          return nil unless match

          file, line_number, content = match.captures
          {
            file: file.sub("#{@root}/", ''),
            line_number: line_number.to_i,
            content: content
          }
        end

        # Builds the CLI command string.
        class CommandBuilder
          def initialize(params)
            @pattern = params[:pattern]
            @path = params[:search_path]
            @file_type = params[:file_type]
            @max = params[:max_results]
          end

          def build
            cmd = ['rg', '--no-heading', '--line-number', '--max-count', @max.to_s]
            cmd.concat(excluded_paths)
            cmd.concat(secret_excludes)
            cmd.concat(file_type_filters)
            cmd.push(@pattern, @path)
          end

          private

          def excluded_paths
            RailsAiBridge.configuration.excluded_paths.flat_map { |path| ['--glob', "!#{path}"] }
          end

          def secret_excludes
            %w[*.key *.pem *.p12 *.pfx *.crt .env .env.*].flat_map { |glob| ['--glob', "!#{glob}"] }
          end

          def file_type_filters
            if @file_type
              ['--type-add', "custom:*.#{@file_type}", '--type', 'custom']
            else
              SearchCode.allowed_search_file_types.flat_map { |ext| ['--glob', "*.#{ext}"] }
            end
          end
        end
      end
    end
  end
end
