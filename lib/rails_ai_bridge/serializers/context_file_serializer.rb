# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Orchestrates writing context files to disk in various formats.
    # Supports: CLAUDE.md, .cursorrules, .windsurfrules, .github/copilot-instructions.md, JSON
    # Also generates split rule files for AI tools that support them.
    class ContextFileSerializer
      attr_reader :context, :format, :split_rules

      FORMAT_MAP = {
        claude: 'CLAUDE.md',
        codex: 'AGENTS.md',
        cursor: '.cursorrules',
        windsurf: '.windsurfrules',
        copilot: '.github/copilot-instructions.md',
        json: '.ai-context.json',
        gemini: 'GEMINI.md'
      }.freeze

      def initialize(context, format: :all, split_rules: true)
        @context     = context
        @format      = format
        @split_rules = split_rules
      end

      # Write context files, skipping unchanged ones.
      # @return [Hash] { written: [paths], skipped: [paths] }
      def call
        formats = format == :all ? FORMAT_MAP.keys : Array(format)
        output_dir = RailsAiBridge.configuration.output_dir_for(Rails.application)
        written = []
        skipped = []

        formats.each do |fmt|
          filename = FORMAT_MAP[fmt]
          unless filename
            valid = FORMAT_MAP.keys.join(', ')
            raise ArgumentError, "Unknown format: #{fmt}. Valid formats: #{valid}"
          end

          filepath = File.join(output_dir, filename)

          # Ensure subdirectory exists (e.g. .github/)
          FileUtils.mkdir_p(File.dirname(filepath))

          content = serialize(fmt)

          if File.exist?(filepath) && File.read(filepath) == content
            skipped << filepath
          else
            File.write(filepath, content)
            written << filepath
          end
        end

        generate_split_rules(formats, output_dir, written, skipped) if split_rules

        { written: written, skipped: skipped }
      end

      private

      def serialize(fmt)
        Providers::Factory.for(fmt, context).call
      end

      def generate_split_rules(formats, output_dir, written, skipped)
        formats.each do |fmt|
          result = Providers::Factory.split_rules_for(fmt, context).call(output_dir)
          written.concat(result[:written])
          skipped.concat(result[:skipped])
        end
      end
    end
  end
end
