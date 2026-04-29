# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Maps format symbols to serializer instances without hardcoded case/if dispatch.
      class Factory
        REGISTRY = {
          json: ->(ctx) { JsonSerializer.new(ctx) },
          claude: ->(ctx) { Providers::ClaudeSerializer.new(ctx) },
          codex: ->(ctx) { Providers::CodexSerializer.new(ctx) },
          cursor: ->(ctx) { Providers::RulesSerializer.new(ctx) },
          windsurf: ->(ctx) { Providers::WindsurfSerializer.new(ctx) },
          gemini: ->(ctx) { Providers::GeminiSerializer.new(ctx) },
          copilot: ->(ctx) { Providers::CopilotSerializer.new(ctx) }
        }.freeze

        SPLIT_REGISTRY = {
          claude: ->(ctx) { Providers::ClaudeRulesSerializer.new(ctx) },
          codex: ->(ctx) { Providers::CodexSupportSerializer.new(ctx) },
          cursor: ->(ctx) { Providers::CursorRulesSerializer.new(ctx) },
          windsurf: ->(ctx) { Providers::WindsurfRulesSerializer.new(ctx) },
          copilot: ->(ctx) { Providers::CopilotInstructionsSerializer.new(ctx) }
        }.freeze

        # Defence-in-depth fallback for unrecognised format keys.
        # Not reachable through ContextFileSerializer (which validates formats first);
        # only triggered when Factory.for is called directly with an unknown symbol.
        class NullStrategy
          def initialize(context) = (@context = context)
          def call = MarkdownSerializer.new(@context).call
        end

        # Returns empty arrays for formats with no split-rules directory.
        class NullSplitRulesStrategy
          def call(_output_dir) = { written: [], skipped: [] }
        end

        # @param fmt [Symbol] Format key (e.g. :claude, :cursor).
        # @param context [Hash] Introspection hash.
        # @return [#call] Serializer object for the main context file.
        def self.for(fmt, context)
          REGISTRY.fetch(fmt) { ->(ctx) { NullStrategy.new(ctx) } }.call(context)
        end

        # @param fmt [Symbol] Format key.
        # @param context [Hash] Introspection hash.
        # @return [#call] Split-rules serializer, or {NullSplitRulesStrategy} when none exists.
        def self.split_rules_for(fmt, context)
          SPLIT_REGISTRY.fetch(fmt) { ->(_ctx) { NullSplitRulesStrategy.new } }.call(context)
        end
      end
    end
  end
end
