# frozen_string_literal: true

require 'open3'

module RailsAiBridge
  module Tools
    class SearchCode
      # Executes codebase searches using ripgrep.
      class RipgrepSearch
        # @param params [Hash] search parameters with keys +:root+, +:pattern+, +:search_path+, +:file_type+, +:max_results+
        def initialize(params)
          @params = params
          @root = params[:root]
        end

        # Executes the ripgrep search and parses results.
        #
        # @return [Array<Hash>] array of result hashes with +:file+, +:line_number+, +:content+
        def call
          cmd = CommandBuilder.new(@params).build
          output, _status = Open3.capture2(*cmd, err: File::NULL)
          parse_output(output)
        rescue StandardError => error
          [{ file: 'error', line_number: 0, content: error.message }]
        end

        private

        # Parses the raw ripgrep output into structured result hashes.
        #
        # @param output [String] raw ripgrep stdout
        # @return [Array<Hash>] parsed results
        def parse_output(output)
          output.lines.filter_map { |line| parse_line(line) }
        end

        # Parses a single line of ripgrep output (file:line:content).
        #
        # @param line [String] a single output line
        # @return [Hash, nil] parsed result or nil if the line doesn't match
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
          # Extensions and globs that should never be searched (lowercase and uppercase variants).
          SECRET_EXCLUDES = %w[
            *.key *.KEY
            *.pem *.PEM
            *.p12 *.P12
            *.pfx *.PFX
            *.crt *.CRT
            .env .env.* .ENV .ENV.*
          ].freeze

          # @param params [Hash] search parameters with keys +:pattern+, +:search_path+, +:file_type+, +:max_results+
          def initialize(params)
            @pattern = params[:pattern]
            @path = params[:search_path]
            @file_type = params[:file_type]
            @max = params[:max_results]
          end

          # Builds the full ripgrep command array.
          #
          # @return [Array<String>] command tokens for +Open3.capture2+
          def build
            cmd = ['rg', '--no-heading', '--line-number', '--max-count', @max.to_s]
            cmd.concat(excluded_path_flags)
            cmd.concat(secret_exclude_flags)
            cmd.concat(file_type_filters)
            cmd.push(@pattern, @path)
          end

          private

          # Builds --glob flags for user-configured excluded paths.
          #
          # @return [Array<String>] glob flag tokens
          # :reek:UtilityFunction
          def excluded_path_flags
            RailsAiBridge.configuration.excluded_paths.flat_map { |path| ['--glob', "!#{path}"] }
          end

          # Builds --glob flags to exclude secret file patterns.
          #
          # @return [Array<String>] glob flag tokens
          # :reek:UtilityFunction
          def secret_exclude_flags
            SECRET_EXCLUDES.flat_map { |glob| ['--glob', "!#{glob}"] }
          end

          # Builds --type or --glob flags for file type filtering.
          #
          # @return [Array<String>] type/glob flag tokens
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
