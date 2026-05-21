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
      # @param on_conflict [:overwrite, :skip, :prompt, #call] conflict resolution strategy;
      #   any object responding to +:call+ is invoked with the filepath and must return a
      #   truthy value to allow overwriting
      # @raise [ArgumentError] when +on_conflict+ is not a recognised symbol or callable
      def initialize(context, format: :all, split_rules: true, on_conflict: :overwrite)
        @context     = context
        @format      = format
        @split_rules = split_rules
        @conflict_policy = ConflictPolicy.build(on_conflict)
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

        timestamp_now = Time.now.utc.iso8601
        fingerprint = Fingerprinter.source_fingerprint(Rails.application)

        formats.each do |fmt|
          process_format(fmt, output_dir, timestamp_now, fingerprint, written, skipped)
        end

        generate_split_rules(formats, output_dir, written, skipped) if split_rules

        { written: written, skipped: skipped }
      end

      private

      # :reek:LongParameterList
      # Processes a single format and writes or skips it.
      def process_format(fmt, output_dir, timestamp_now, fingerprint, written, skipped)
        filename = FORMAT_MAP[fmt]
        unless filename
          valid = FORMAT_MAP.keys.join(', ')
          raise ArgumentError, "Unknown format: #{fmt}. Valid formats: #{valid}"
        end

        filepath = File.join(output_dir, filename)
        FileUtils.mkdir_p(File.dirname(filepath))

        writer = FreshnessWriter.new(fmt, serialize(fmt), fingerprint, timestamp_now)
        writer.write_to(filepath, @conflict_policy, written, skipped)
      end

      # @param filepath [String] candidate output path
      # @return [Boolean] +true+ when the file should be overwritten
      def overwrite?(filepath)
        @conflict_policy.overwrite?(filepath)
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

      # Encapsulates format-specific freshness metadata embedding and file write logic.
      # Separating this from ContextFileSerializer removes ControlParameter and UtilityFunction
      # reek warnings from the serializer (the fmt-branching now lives in the right class).
      class FreshnessWriter
        def initialize(fmt, raw_content, fingerprint, timestamp_now)
          @fmt         = fmt
          @raw_content = raw_content
          @fingerprint = fingerprint
          @timestamp_now = timestamp_now
        end

        # :reek:LongParameterList
        def write_to(filepath, conflict_policy, written, skipped)
          existing_content = read_existing(filepath)
          timestamp_to_use = resolve_timestamp(existing_content)
          candidate = build_candidate_content(timestamp_to_use)

          if skip?(filepath, existing_content, candidate, conflict_policy)
            skipped << filepath
          else
            write_file(filepath, candidate, timestamp_to_use)
            written << filepath
          end
        end

        private

        def read_existing(filepath)
          File.exist?(filepath) ? File.read(filepath) : nil
        end

        def resolve_timestamp(existing_content)
          return @timestamp_now unless existing_content

          embedded_fp, embedded_ts = FreshnessHeader.extract_metadata_for(@fmt, existing_content)
          embedded_fp == @fingerprint && embedded_ts ? embedded_ts : @timestamp_now
        end

        def build_candidate_content(timestamp)
          FreshnessHeader.embed_for(@fmt, @raw_content, timestamp, @fingerprint)
        end

        def skip?(filepath, existing_content, candidate, conflict_policy)
          existing_content && (existing_content == candidate || !conflict_policy.overwrite?(filepath))
        end

        def write_file(filepath, candidate, timestamp_to_use)
          final_content = timestamp_to_use == @timestamp_now ? candidate : build_candidate_content(@timestamp_now)
          File.write(filepath, final_content)
        end
      end
      private_constant :FreshnessWriter

      # Normalizes conflict behavior for output files.
      class ConflictPolicy
        # @param strategy [:overwrite, :skip, :prompt, #call]
        # @return [ConflictPolicy, PromptConflictPolicy, CallableConflictPolicy]
        # @raise [ArgumentError] when the strategy is not supported
        def self.build(strategy)
          return PromptConflictPolicy.new if strategy == :prompt
          return new(strategy) if VALID_ON_CONFLICT_SYMBOLS.include?(strategy)

          CallableConflictPolicy.new(strategy.method(:call))
        rescue NameError
          invalid_strategy!(strategy)
        end

        def self.invalid_strategy!(strategy)
          raise ArgumentError, "on_conflict must be :overwrite, :skip, :prompt, or a callable; got #{strategy.inspect}"
        end
        private_class_method :invalid_strategy!

        def initialize(strategy)
          @strategy = strategy
        end

        def overwrite?(_filepath)
          case @strategy
          when :overwrite then true
          when :skip      then false
          end
        end
      end

      # Interactive conflict policy used only for explicit `on_conflict: :prompt`.
      class PromptConflictPolicy
        def initialize(input: $stdin, output: $stdout)
          @input = input
          @output = output
        end

        def overwrite?(filepath)
          @output.print "  Overwrite #{filepath}? [y/N] "
          @output.flush
          @input.gets.to_s.strip.downcase == 'y'
        end
      end

      # Adapter for user-provided conflict resolver objects.
      class CallableConflictPolicy
        def initialize(callable)
          @callable = callable
        end

        def overwrite?(filepath)
          @callable.call(filepath)
        end
      end
      private_constant :ConflictPolicy, :PromptConflictPolicy, :CallableConflictPolicy
    end
  end
end
