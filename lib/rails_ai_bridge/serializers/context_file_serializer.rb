# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Writes compact (or full) assistant context files under {Rails.root} or +config.output_dir+.
    #
    # Dispatches to format-specific serializers and, for Copilot, merges into a managed HTML comment region
    # so host edits outside that block are preserved. Also emits “split” rule files (.claude/rules/, etc.)
    # when the primary format for that assistant is included in the run.
    #
    # @see AssistantFormatsPreference
    class ContextFileSerializer
      attr_reader :context, :format

      # Maps logical format keys to a single top-level filename under the output directory.
      FORMAT_MAP = {
        claude:    "CLAUDE.md",
        codex:     "AGENTS.md",
        cursor:    ".cursorrules",
        windsurf:  ".windsurfrules",
        copilot:   ".github/copilot-instructions.md",
        json:      ".ai-context.json"
      }.freeze

      # Start marker for gem-managed Copilot markdown (see {#write_copilot_with_merge}).
      COPILOT_MANAGED_BEGIN = "<!-- rails-ai-bridge:begin managed -->"
      # End marker for gem-managed Copilot markdown.
      COPILOT_MANAGED_END = "<!-- rails-ai-bridge:end managed -->"
      # Matches one managed block for replacement.
      COPILOT_MANAGED_BLOCK = /#{Regexp.escape(COPILOT_MANAGED_BEGIN)}.*?#{Regexp.escape(COPILOT_MANAGED_END)}/m

      # @param context [Hash] introspection snapshot passed to format serializers
      # @param format [Symbol, Array<Symbol>] +:all+, a single key from {FORMAT_MAP}, or an array of keys
      def initialize(context, format: :all)
        @context = context
        @format  = format
      end

      # Writes requested files and split rules, skipping byte-identical paths.
      #
      # @return [Hash{Symbol => Array<String>}] +:written+ and +:skipped+ file paths
      def call
        formats = normalize_format_list(@format)
        output_dir = RailsAiBridge.configuration.output_dir_for(Rails.application)
        written = []
        skipped = []

        formats.each do |fmt|
          filename = FORMAT_MAP[fmt]
          unless filename
            valid = FORMAT_MAP.keys.map(&:to_s).join(", ")
            raise ArgumentError, "Unknown format: #{fmt}. Valid formats: #{valid}"
          end

          filepath = File.join(output_dir, filename)
          FileUtils.mkdir_p(File.dirname(filepath))

          content = serialize(fmt)

          if fmt == :copilot
            write_copilot_with_merge(filepath, content, written, skipped)
          elsif File.exist?(filepath) && File.read(filepath) == content
            skipped << filepath
          else
            File.write(filepath, content)
            written << filepath
          end
        end

        generate_split_rules(formats, output_dir, written, skipped)

        { written: written, skipped: skipped }
      end

      private

      # @param format [Object]
      # @raise [ArgumentError] when an unknown format key appears in an array
      # @return [Array<Symbol>]
      def normalize_format_list(format)
        case format
        when :all
          FORMAT_MAP.keys
        when Array
          list = format.map(&:to_sym).uniq
          unknown = list - FORMAT_MAP.keys
          raise ArgumentError, "Unknown format(s): #{unknown.join(", ")}" if unknown.any?

          list
        else
          [ format ].flatten.map(&:to_sym)
        end
      end

      # @param inner_markdown [String]
      # @return [String]
      def wrap_copilot_managed(inner_markdown)
        "#{COPILOT_MANAGED_BEGIN}\n#{inner_markdown.to_s.strip}\n#{COPILOT_MANAGED_END}\n"
      end

      # Updates +copilot-instructions.md+ by replacing the managed block, or skips/warns per +RAILS_AI_BRIDGE_COPILOT_MERGE+.
      #
      # @param filepath [String]
      # @param inner_content [String] serialized Copilot body (without managed markers)
      # @param written [Array<String>] mutated with path if written
      # @param skipped [Array<String>] mutated with path if skipped
      # @return [void]
      def write_copilot_with_merge(filepath, inner_content, written, skipped)
        wrapped = wrap_copilot_managed(inner_content)
        mode = ENV.fetch("RAILS_AI_BRIDGE_COPILOT_MERGE", "").to_s.downcase

        if File.exist?(filepath)
          existing = File.read(filepath)
          if existing.match?(COPILOT_MANAGED_BLOCK)
            updated = existing.sub(COPILOT_MANAGED_BLOCK, wrapped.strip)
          elsif mode == "overwrite"
            updated = wrapped
          elsif mode == "skip"
            warn "[rails-ai-bridge] Skipping #{filepath} (no managed markers; RAILS_AI_BRIDGE_COPILOT_MERGE=skip)."
            skipped << filepath
            return
          else
            warn "[rails-ai-bridge] Skipping #{filepath}: existing file has no #{COPILOT_MANAGED_BEGIN}/END managed block. " \
                 "Set RAILS_AI_BRIDGE_COPILOT_MERGE=overwrite to replace, or wrap your file manually."
            skipped << filepath
            return
          end
        else
          updated = wrapped
        end

        if File.exist?(filepath) && File.read(filepath) == updated
          skipped << filepath
        else
          File.write(filepath, updated)
          written << filepath
        end
      end

      # @param fmt [Symbol]
      # @return [String]
      def serialize(fmt)
        case fmt
        when :json     then JsonSerializer.new(context).call
        when :claude   then ClaudeSerializer.new(context).call
        when :codex    then CodexSerializer.new(context).call
        when :cursor   then RulesSerializer.new(context).call
        when :windsurf then WindsurfSerializer.new(context).call
        when :copilot  then CopilotSerializer.new(context).call
        else MarkdownSerializer.new(context).call
        end
      end

      # @param formats [Array<Symbol>]
      # @param output_dir [String]
      # @param written [Array<String>]
      # @param skipped [Array<String>]
      # @return [void]
      def generate_split_rules(formats, output_dir, written, skipped)
        if formats.include?(:claude)
          result = ClaudeRulesSerializer.new(context).call(output_dir)
          written.concat(result[:written])
          skipped.concat(result[:skipped])
        end

        if formats.include?(:codex)
          result = CodexSupportSerializer.new(context).call(output_dir)
          written.concat(result[:written])
          skipped.concat(result[:skipped])
        end

        if formats.include?(:cursor)
          result = CursorRulesSerializer.new(context).call(output_dir)
          written.concat(result[:written])
          skipped.concat(result[:skipped])
        end

        if formats.include?(:windsurf)
          result = WindsurfRulesSerializer.new(context).call(output_dir)
          written.concat(result[:written])
          skipped.concat(result[:skipped])
        end

        if formats.include?(:copilot)
          result = CopilotInstructionsSerializer.new(context).call(output_dir)
          written.concat(result[:written])
          skipped.concat(result[:skipped])
        end
      end
    end
  end
end
