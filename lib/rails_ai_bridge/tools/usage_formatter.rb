# frozen_string_literal: true

module RailsAiBridge
  module Tools
    # Shared message constants and output formatting for the +rails_use_skill+
    # and +rails_use_agent+ tools.
    #
    # Single responsibility: render resolved pack content as an in-context
    # application directive — an intent header, an optional deprecation
    # notice, the full content, and a follow-through footer. Resolver
    # plumbing stays in the tool classes themselves.
    module UsageFormatter
      include Registry::Truncatable

      NO_REGISTRY_MESSAGE = "No registry manifest found at `%<path>s`.\n\n" \
                            'Set up a registry manifest to load skill packs (see docs/skill-registry-guide.md).'
      NOT_FOUND_SKILL_MESSAGE = "Skill `%<name>s` not found in the loaded skill packs.\n\n" \
                                'Use `rails_list_registry type=skills` to see available skills.'
      NOT_FOUND_AGENT_MESSAGE = "Agent `%<name>s` not found in the loaded skill packs.\n\n" \
                                'Use `rails_list_registry type=agents` to see available agents.'

      USAGE_VERBS = {
        skill: 'Applying skill',
        agent: 'Activating agent'
      }.freeze

      USAGE_FOOTERS = {
        skill: '_Work through every step of this skill in order. If a step does not apply, say so explicitly ' \
               'instead of skipping it silently._',
        agent: '_Follow this workflow end to end and respect its hard gates; do not skip steps silently._'
      }.freeze

      # Formats resolved skill/agent content for immediate in-context application.
      #
      # @param resolved [Registry::ResolvedSkill] resolved content (name, pack, content)
      # @param kind [Symbol] +:skill+ or +:agent+
      # @param deprecation_warning [String, nil] warning from a deprecation redirect, if any
      # @return [String] markdown application directive
      # :reek:FeatureEnvy -- output assembly necessarily centres on the rendered section list
      def format_usage(resolved, kind:, deprecation_warning: nil)
        [
          usage_header(resolved, kind),
          '',
          deprecation_block(deprecation_warning),
          resolved.content,
          '',
          '---',
          USAGE_FOOTERS.fetch(kind)
        ].compact.join("\n")
      end

      private

      # @api private
      def usage_header(resolved, kind)
        safe_name = sanitize_markdown(resolved.name)
        safe_pack = sanitize_markdown(resolved.pack)

        "# #{USAGE_VERBS.fetch(kind)}: #{safe_name}\n" \
          "_Source pack: **#{safe_pack}** — apply the guidance below directly to the current task._"
      end

      # @api private
      # :reek:NilCheck -- optional section rendered only when a redirect warning exists
      def deprecation_block(warning)
        return nil unless warning

        "> **Deprecated:** #{warning}\n"
      end
    end
  end
end
