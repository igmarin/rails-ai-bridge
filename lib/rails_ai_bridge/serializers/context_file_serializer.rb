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

      VALID_ON_CONFLICT_SYMBOLS = %i[overwrite skip prompt].freeze

      # @param context [Hash] introspection context from {RailsAiBridge.introspect}
      # @param format [Symbol, Array<Symbol>] format(s) to generate
      # @param split_rules [Boolean] whether to generate per-assistant rule directories
      # @param on_conflict [:overwrite, :skip, :prompt, Proc] conflict resolution strategy
      # @raise [ArgumentError] when +on_conflict+ is not a recognised symbol or callable
      def initialize(context, format: :all, split_rules: true, on_conflict: :overwrite)
        unless VALID_ON_CONFLICT_SYMBOLS.include?(on_conflict) || on_conflict.respond_to?(:call)
          raise ArgumentError,
                "on_conflict must be :overwrite, :skip, :prompt, or a callable; got #{on_conflict.inspect}"
        end

        @context     = context
        @format      = format
        @split_rules = split_rules
        @on_conflict = on_conflict
      end

      # Write context files to the configured output directory, skipping unchanged ones.
      #
      # @return [Hash{Symbol => Array<String>}] +:written+ paths and +:skipped+ paths
      # @raise [ArgumentError] when an unrecognised format symbol is encountered
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

          unchanged = File.exist?(filepath) && File.read(filepath) == content
          if !unchanged && (!File.exist?(filepath) || overwrite?(filepath))
            File.write(filepath, content)
            written << filepath
          else
            skipped << filepath
          end
        end

        generate_split_rules(formats, output_dir, written, skipped) if split_rules

        { written: written, skipped: skipped }
      end

      private

      # @param filepath [String] candidate output path
      # @return [Boolean] +true+ when the file should be overwritten
      def overwrite?(filepath)
        case @on_conflict
        when :overwrite then true
        when :skip      then false
        when :prompt
          $stdout.print "  Overwrite #{filepath}? [y/N] "
          $stdout.flush
          $stdin.gets.to_s.strip.downcase == 'y'
        when Proc then @on_conflict.call(filepath)
        end
      end

      # @param fmt [Symbol] format key
      # @return [String] rendered file content
      def serialize(fmt)
        Providers::Factory.for(fmt, context).call
      end

      # @param formats [Array<Symbol>] format keys being written
      # @param output_dir [String] root output directory
      # @param written [Array<String>] accumulator for written paths
      # @param skipped [Array<String>] accumulator for skipped paths
      # @return [void]
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
