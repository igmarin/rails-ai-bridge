# frozen_string_literal: true

module RailsAiBridge
  module Generators
    # Resolves the install profile either from a CLI option or an interactive prompt.
    # Accepts any object that responds to +say+ and +ask+ as the shell dependency
    # (typically the generator itself, enabling seamless stubbing in tests).
    class ProfileResolver
      PROFILE_OPTIONS = {
        'custom' => {
          description: 'Pick formats interactively (per-format prompts).',
          formats: nil,
          split_rules: true
        },
        'minimal' => {
          description: 'Thin Cursor/Windsurf/Claude/Copilot/Gemini shims, no split rule directories.',
          formats: %i[claude cursor windsurf copilot gemini],
          split_rules: false
        },
        'full' => {
          description: 'All formats plus split rule directories for every assistant.',
          formats: RailsAiBridge::Serializers::ContextFileSerializer::FORMAT_MAP.keys,
          split_rules: true
        },
        'mcp' => {
          description: 'Only .mcp.json now — generate assistant files later.',
          formats: [],
          split_rules: false
        }
      }.freeze

      def initialize(option, shell:)
        @option = option&.to_s&.downcase
        @shell  = shell
      end

      # Resolves the profile, raising +ArgumentError+ when a CLI option names an
      # unrecognised profile (fail-fast) or falling back to +"custom"+ with a
      # yellow warning when an unrecognised answer is typed interactively.
      #
      # @return [String] resolved profile name (one of the {PROFILE_OPTIONS} keys)
      # @raise [ArgumentError] when a CLI +--profile+ value is not in {PROFILE_OPTIONS}
      def call
        return resolve_from_option if @option

        resolve_interactively
      end

      # @param profile [String] profile name
      # @return [Array<Symbol>, nil] format symbols for the profile, or +nil+ for unknown profiles
      def self.formats_for(profile)
        PROFILE_OPTIONS.fetch(profile, nil)&.dig(:formats)&.dup
      end

      # @param profile [String] profile name
      # @return [Boolean, nil] whether to generate split-rules directories, or +nil+ for unknown profiles
      def self.split_rules_for(profile)
        PROFILE_OPTIONS.fetch(profile, nil)&.dig(:split_rules)
      end

      # @param profile [String] profile name
      # @return [String, nil] human-readable description, or +nil+ for unknown profiles
      def self.description_for(profile)
        PROFILE_OPTIONS.fetch(profile, nil)&.dig(:description)
      end

      private

      # Validates the CLI-supplied option and raises immediately on unknown values
      # so callers receive a clear error rather than a silent fallback.
      #
      # @raise [ArgumentError] when +@option+ is not a key of {PROFILE_OPTIONS}
      def resolve_from_option
        return @option if PROFILE_OPTIONS.key?(@option)

        valid = PROFILE_OPTIONS.keys.join(', ')
        @shell.say "Unknown --profile '#{@option}'. Valid profiles: #{valid}.", :red
        raise ArgumentError, "Unknown --profile '#{@option}'. Valid profiles: #{valid}."
      end

      def resolve_interactively
        show_options
        answer = @shell.ask('Choose profile (default: custom):').to_s.strip.downcase
        answer = 'custom' if answer.empty?
        normalize(answer)
      end

      def normalize(option)
        return option if PROFILE_OPTIONS.key?(option)

        @shell.say "Unknown profile '#{option}'. Falling back to custom.", :yellow
        'custom'
      end

      def show_options
        @shell.say ''
        @shell.say 'Install profiles:', :yellow
        PROFILE_OPTIONS.each do |key, config|
          @shell.say format('  %-7<profile>s %<desc>s', profile: key, desc: config[:description])
        end
      end
    end
  end
end
