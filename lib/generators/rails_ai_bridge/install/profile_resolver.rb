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

      # @return [String] Resolved profile name (one of the {PROFILE_OPTIONS} keys).
      def call
        return resolve_from_option if @option

        resolve_interactively
      end

      # @return [Array<Symbol>, nil] Format symbols for the given profile.
      def self.formats_for(profile)
        PROFILE_OPTIONS.fetch(profile)&.dig(:formats)&.dup
      end

      # @return [Boolean] Whether to generate split-rules directories for the profile.
      def self.split_rules_for(profile)
        PROFILE_OPTIONS.fetch(profile)&.dig(:split_rules)
      end

      # @return [String] Human-readable description of the profile.
      def self.description_for(profile)
        PROFILE_OPTIONS.fetch(profile)&.dig(:description)
      end

      private

      def resolve_from_option
        normalize(@option)
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
