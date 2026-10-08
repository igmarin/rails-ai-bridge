# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Deprecated assistant files that are no longer written unless +config.output.legacy_agent_files+ is on.
    #
    # Cursor reads +.cursor/rules/+ and +AGENTS.md+, Devin does not read +.devinrules+, and Codex reads only
    # +AGENTS.md+. The split-rules directories of the Cursor and Devin formats are still written; only their
    # single main file is skipped. For Codex, only the +.codex/README.md+ split output is skipped.
    module LegacyAgentFiles
      MAIN_FORMATS = %i[cursor devin].freeze
      SPLIT_FORMATS = %i[codex].freeze
      WARNING = '[rails-ai-bridge] DEPRECATION: config.output.legacy_agent_files writes ' \
                '.cursorrules, .devinrules, and .codex/README.md, which no assistant needs. ' \
                'They will be removed in 6.0.'

      class << self
        # @param fmt [Symbol] format key
        # @return [Boolean] +true+ when the format's main file is deprecated output and the flag is off
        def skip_main?(fmt) = skipped?(fmt, MAIN_FORMATS)

        # @param fmt [Symbol] format key
        # @return [Boolean] +true+ when the format's split-rules output is deprecated and the flag is off
        def skip_split?(fmt) = skipped?(fmt, SPLIT_FORMATS)

        # Prints the deprecation notice once per process when the flag writes deprecated files.
        #
        # @param formats [Array<Symbol>] formats being written
        # @return [void]
        def warn_once(formats)
          return unless enabled? && formats.intersect?(MAIN_FORMATS + SPLIT_FORMATS)
          return if @warned

          @warned = true
          warn(WARNING)
        end

        # Clears the once-per-process memo (for specs).
        #
        # @return [void]
        def reset_warning!
          @warned = false
        end

        private

        def enabled?
          RailsAiBridge.configuration.legacy_agent_files
        end

        def skipped?(fmt, legacy_formats)
          legacy_formats.include?(fmt) && !enabled?
        end
      end
    end
  end
end
