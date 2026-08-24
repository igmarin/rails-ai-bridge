# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Orchestrates writing context files to disk in various formats.
    # Supports: CLAUDE.md, .cursorrules, .devinrules, .github/copilot-instructions.md, JSON
    # Also generates split rule files for AI tools that support them.
    class ContextFileSerializer
      attr_reader :context, :format, :split_rules

      FORMAT_MAP = {
        claude: 'CLAUDE.md',
        codex: 'AGENTS.md',
        cursor: '.cursorrules',
        devin: '.devinrules',
        copilot: '.github/copilot-instructions.md',
        json: '.ai-context.json',
        gemini: 'GEMINI.md'
      }.freeze

      VALID_ON_CONFLICT_SYMBOLS = %i[overwrite skip prompt].freeze

      # Managed regions are markdown-comment delimited, so JSON output never participates.
      UNMANAGEABLE_FORMATS = %i[json].freeze

      # @param context [Hash] introspection context from {RailsAiBridge.introspect}
      # @param format [Symbol, Array<Symbol>] format(s) to generate
      # @param split_rules [Boolean] whether to generate per-assistant rule directories
      # @param on_conflict [:overwrite, :skip, :prompt, #call] conflict resolution strategy;
      #   any object responding to +:call+ is invoked with the filepath and must return a
      #   truthy value to allow overwriting
      # @param managed_region [Boolean, nil] confine generated output to a marked region so
      #   hand-authored content in the file survives; +nil+ inherits +config.output.managed_region+
      # @raise [ArgumentError] when +on_conflict+ is not a recognised symbol or callable
      def initialize(context, format: :all, split_rules: true, on_conflict: :overwrite, managed_region: nil)
        @context     = context
        @format      = format
        @split_rules = split_rules
        @conflict_policy = ConflictPolicy.build(on_conflict)
        # archspec:disable dependencies.forbid -- FP: RailsAiBridge namespace accessor, not a cross-component dependency
        # archspec:disable dependencies.no_cycles -- FP: cycle from namespace reopening, not a real cross-component cycle
        @managed_region = managed_region.nil? ? RailsAiBridge.configuration.managed_region : managed_region
        # archspec:enable dependencies.forbid
        # archspec:enable dependencies.no_cycles
      end

      # Write context files to the configured output directory, skipping unchanged ones.
      #
      # @return [Hash{Symbol => Array<String>}] +:written+ paths and +:skipped+ paths
      # @raise [ArgumentError] when an unrecognised format symbol is encountered
      def call
        formats = format == :all ? FORMAT_MAP.keys : Array(format)
        # archspec:disable-next-line dependencies.forbid -- FP: RailsAiBridge is the reopened gem namespace; .configuration accessor is not a cross-component dependency
        output_dir = RailsAiBridge.configuration.output_dir_for(AppScope.current_app)
        written = []
        skipped = []

        timestamp_now = Time.now.utc.iso8601
        fingerprint = Fingerprinter.source_fingerprint(AppScope.current_app)

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

        writer = FreshnessWriter.new(fmt, serialize(fmt), fingerprint, timestamp_now, layout: layout_for(fmt))
        writer.write_to(filepath, @conflict_policy, written, skipped)
      end

      # @param fmt [Symbol] format key
      # @return [WholeFileLayout, ManagedRegionLayout] how the payload occupies the file
      def layout_for(fmt)
        managed_region?(fmt) ? ManagedRegionLayout.new : WholeFileLayout.new
      end

      # @param fmt [Symbol] format key
      # @return [Boolean] +true+ when this format should write into a marked region
      def managed_region?(fmt)
        @managed_region && UNMANAGEABLE_FORMATS.exclude?(fmt)
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

      # Default layout: the generated payload is the entire file.
      class WholeFileLayout
        # @param existing [String, nil] current file content
        # @return [String, nil] previously generated payload
        def previous_payload(existing) = existing

        # @param _existing [String, nil] current file content (discarded)
        # @param payload [String] freshly generated content
        # @return [String] content to write
        def compose(_existing, payload) = payload
      end

      # Managed-region layout: only the marked block belongs to the gem; anything the
      # user wrote above or below it is carried through untouched.
      class ManagedRegionLayout
        # @param existing [String, nil] current file content
        # @return [String, nil] payload inside the markers, the whole file when it is
        #   unmarked gem output, or +nil+ when the file is hand-authored
        def previous_payload(existing)
          ManagedRegion.extract(existing) || whole_file_output(existing)
        end

        # @param existing [String, nil] current file content
        # @param payload [String] freshly generated content
        # @return [String] content to write
        def compose(existing, payload)
          ManagedRegion.merge(whole_file_output(existing) ? nil : existing, payload)
        end

        private

        # A file led by the freshness header is prior whole-file output from this gem, so
        # none of it is hand-authored. Replacing it keeps the first run after opting in
        # from appending a second copy of the context below the stale one — a duplicate
        # that would then never refresh, because it now reads as user content.
        #
        # Memoized per instance so the header check runs once per write cycle, not twice
        # (previous_payload + compose both call it).
        #
        # @param existing [String, nil] current file content
        # @return [String, nil] +existing+ when it is unmarked gem output
        def whole_file_output(existing)
          return @cached_result if @cached_for == existing

          @cached_for = existing
          @cached_result = existing if existing && !ManagedRegion.markers?(existing) && FreshnessHeader.gem_generated?(existing)
        end
      end
      private_constant :WholeFileLayout, :ManagedRegionLayout

      # Encapsulates format-specific freshness metadata embedding and file write logic.
      # Separating this from ContextFileSerializer removes ControlParameter and UtilityFunction
      # reek warnings from the serializer (the fmt-branching now lives in the right class).
      class FreshnessWriter
        # @param fmt [Symbol] format key
        # @param raw_content [String] serialized content before freshness embedding
        # @param fingerprint [String] 12-char source fingerprint
        # @param timestamp_now [String] ISO 8601 UTC timestamp
        # @param layout [#previous_payload, #compose] how the payload occupies the file
        def initialize(fmt, raw_content, fingerprint, timestamp_now, layout: WholeFileLayout.new)
          @fmt         = fmt
          @raw_content = raw_content
          @fingerprint = fingerprint
          @timestamp_now = timestamp_now
          @layout = layout
        end

        # Writes the file to disk, skipping if unchanged or blocked by the conflict policy.
        #
        # @param filepath [String] output file path
        # @param conflict_policy [ConflictPolicy] resolution strategy
        # @param written [Array<String>] accumulator for written paths
        # @param skipped [Array<String>] accumulator for skipped paths
        # @return [void]
        # :reek:LongParameterList
        def write_to(filepath, conflict_policy, written, skipped)
          existing_content = read_existing(filepath)
          timestamp_to_use = resolve_timestamp(@layout.previous_payload(existing_content))
          candidate = compose(existing_content, timestamp_to_use)

          if skip?(filepath, existing_content, candidate, conflict_policy)
            skipped << filepath
          else
            write_file(filepath, existing_content, candidate, timestamp_to_use)
            written << filepath
          end
        end

        private

        def read_existing(filepath)
          File.exist?(filepath) ? File.read(filepath) : nil
        end

        # @param previous_payload [String, nil] the gem-owned portion of the existing file
        def resolve_timestamp(previous_payload)
          return @timestamp_now unless previous_payload

          embedded_fp, embedded_ts = FreshnessHeader.extract_metadata_for(@fmt, previous_payload)
          embedded_fp == @fingerprint && embedded_ts ? embedded_ts : @timestamp_now
        end

        def build_candidate_content(timestamp)
          FreshnessHeader.embed_for(@fmt, @raw_content, timestamp, @fingerprint)
        end

        # Full file content for the given timestamp, including any hand-authored
        # content the layout preserves.
        def compose(existing_content, timestamp)
          @layout.compose(existing_content, build_candidate_content(timestamp))
        end

        def skip?(filepath, existing_content, candidate, conflict_policy)
          existing_content && (existing_content == candidate || !conflict_policy.overwrite?(filepath))
        end

        # :reek:LongParameterList
        def write_file(filepath, existing_content, candidate, timestamp_to_use)
          final_content = timestamp_to_use == @timestamp_now ? candidate : compose(existing_content, @timestamp_now)
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

        # Determines whether to overwrite a file based on the configured strategy.
        #
        # @param _filepath [String] candidate file path (unused for built-in strategies)
        # @return [Boolean] +true+ when :overwrite, +false+ when :skip
        def overwrite?(_filepath)
          case @strategy
          when :overwrite then true
          when :skip      then false
          end
        end
      end

      # Interactive conflict policy used only for explicit `on_conflict: :prompt`.
      class PromptConflictPolicy
        # @param input [IO] input stream (defaults to $stdin)
        # @param output [IO] output stream (defaults to $stdout)
        def initialize(input: $stdin, output: $stdout)
          @input = input
          @output = output
        end

        # Prompts the user and returns +true+ only if they answer +y+.
        #
        # @param filepath [String] candidate file path
        # @return [Boolean]
        def overwrite?(filepath)
          @output.print "  Overwrite #{filepath}? [y/N] "
          @output.flush
          @input.gets.to_s.strip.downcase == 'y'
        end
      end

      # Adapter for user-provided conflict resolver objects.
      class CallableConflictPolicy
        # @param callable [#call] callable object invoked with filepath
        def initialize(callable)
          @callable = callable
        end

        # Delegates the overwrite decision to the wrapped callable.
        #
        # @param filepath [String] candidate file path
        # @return [Boolean]
        def overwrite?(filepath)
          @callable.call(filepath)
        end
      end
      private_constant :ConflictPolicy, :PromptConflictPolicy, :CallableConflictPolicy
    end
  end
end
