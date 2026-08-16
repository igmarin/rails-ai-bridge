# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # MCP tool that explains a Ruby/Rails symbol from a **local** CodeGraph index.
    #
    # When +.codegraph/+ exists under +Rails.root+, this tool runs +codegraph explore+
    # (or a stubbed explorer in tests) and returns truncated markdown. Missing indexes
    # and CLI failures return a setup message — the tool never raises to the MCP host
    # and never makes network calls.
    #
    # @example Explain a class
    #   rails_explain_symbol query=User
    # @example Alias input
    #   rails_explain_symbol symbol=GetSchema
    class ExplainSymbol < BaseTool
      # Raised by {CliExplorer} when the local +codegraph+ invocation cannot complete.
      class ExploreError < StandardError; end

      INDEX_DIR_NAME = '.codegraph'
      SETUP_HINT = 'Generate a local index with `codegraph init` or `codegraph index` ' \
                   '(no network required), then retry.'
      MISSING_INDEX_MESSAGE = "No local CodeGraph index found at `#{INDEX_DIR_NAME}/`. #{SETUP_HINT}".freeze
      BLANK_QUERY_MESSAGE = 'Provide a `symbol` or `query` string (for example `User` or `User#save`).'

      tool_name 'rails_explain_symbol'
      description 'Explain a Ruby/Rails symbol from the local CodeGraph index (.codegraph/). ' \
                  'Accepts `symbol` or `query`. Returns markdown with source and call paths. ' \
                  'If the index is missing, returns setup instructions. Never contacts the network.'

      input_schema(
        properties: {
          symbol: {
            type: 'string',
            description: 'Symbol name to explain (e.g. "User", "User#save"). Alias of query.'
          },
          query: {
            type: 'string',
            description: 'Symbol name or natural-language question for `codegraph explore`.'
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      class << self
        # Injectable explorer used by tests. Defaults to {CliExplorer}.
        attr_writer :explorer

        # @param symbol [String, nil] symbol name alias for +query+
        # @param query [String, nil] CodeGraph explore query
        # @param _server_context [Object, nil] reserved for MCP transport metadata (unused)
        # @return [MCP::Tool::Response] markdown explanation or a setup/error message
        # @raise [ExploreError] when the local CLI fails (rescued into a tool response)
        # @raise [StandardError] unexpected explorer failures (rescued into a tool response)
        def call(symbol: nil, query: nil, _server_context: nil)
          resolved = resolve_query(symbol, query)
          return text_response(BLANK_QUERY_MESSAGE) if resolved.empty?
          return text_response(MISSING_INDEX_MESSAGE) unless index_present?

          text_response(explorer.explore(resolved))
        rescue ExploreError => error
          text_response(command_failure_message(error))
        rescue StandardError => error
          log_unexpected_error(error)
          text_response(command_failure_message(error))
        end

        # @return [#explore] explorer responding to +explore(query)+
        def explorer
          @explorer ||= CliExplorer.new(root: rails_root)
        end

        # Clears a stubbed explorer so the next call builds the default.
        #
        # @return [void]
        def reset!
          @explorer = nil
        end

        # @return [Boolean] whether +.codegraph/+ exists under the application root
        def index_present?
          Dir.exist?(File.join(rails_root, INDEX_DIR_NAME))
        end

        private

        # @param symbol [String, nil]
        # @param query [String, nil]
        # @return [String] stripped query, preferring +query+ over +symbol+
        def resolve_query(symbol, query)
          first_present(query, symbol)
        end

        # @param values [Array<Object>]
        # @return [String]
        def first_present(*values)
          values.map { |value| value.to_s.strip }.find { |value| !value.empty? }.to_s
        end

        # @return [String] Rails.root as a string
        def rails_root
          Rails.root.to_s
        end

        # @param error [Exception]
        # @return [String]
        def command_failure_message(error)
          "CodeGraph explore failed: #{error.message}. #{SETUP_HINT}"
        end

        # @param error [StandardError]
        # @return [void]
        def log_unexpected_error(error)
          logger = Rails.logger
          return unless logger

          logger.error(error.message)
          logger.error(Array(error.backtrace).first(5).join("\n"))
        end
      end
    end
  end
end
