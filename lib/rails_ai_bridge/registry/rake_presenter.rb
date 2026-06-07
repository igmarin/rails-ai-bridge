# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Formats registry data for CLI output in rake tasks.
    #
    # Single responsibility: converts resolver data into human-readable stdout
    # strings for rake tasks. Does not know about MCP, tools, or configuration.
    # Rake tasks delegate all formatting here to stay DRY with each other.
    #
    # @example
    #   presenter = RakePresenter.new(resolver)
    #   puts presenter.skills_table
    #   puts presenter.resolve_skill_output('code-review', requested_pack: 'rails')
    class RakePresenter
      include Truncatable

      SKILL_NAME_COL  = 30
      PACK_NAME_COL   = 15
      DESC_MAX_LENGTH = 50
      TABLE_WIDTH     = 80

      NO_MANIFEST_MESSAGE = <<~MSG
        No registry manifest found at '%<path>s'.
        Create the file and configure skill packs. See docs/skill-registry-guide.md for details.
      MSG

      # @param resolver [Registry::Resolver] resolved registry
      # @raise [ArgumentError] if resolver is nil
      def initialize(resolver)
        raise ArgumentError, 'RakePresenter requires a resolver; got nil — check registry configuration' if resolver.nil?

        @resolver = resolver
      end

      # @return [String] skills table for stdout, or an error/empty message
      def skills_table
        skills = @resolver.list_skills
        return "No skills are loaded. Check your registry manifest configuration.\n" if skills.empty?

        lines = ["Available Skills (#{skills.length})", '']
        lines << "#{'Skill'.ljust(SKILL_NAME_COL)} #{'Pack'.ljust(PACK_NAME_COL)} Description"
        lines << ('-' * TABLE_WIDTH)
        skills.each do |skill|
          desc = truncate(skill.description, DESC_MAX_LENGTH)
          lines << "#{skill.name.ljust(SKILL_NAME_COL)} #{skill.pack.ljust(PACK_NAME_COL)} #{desc}"
        end
        lines.join("\n")
      end

      # @param name [String] skill name
      # @param requested_pack [String, nil] optional pack the user asked for
      # @return [String] multi-line output including content, or an error message
      def resolve_skill_output(name, requested_pack: nil)
        resolved = @resolver.resolve_skill(name)
        return "Skill '#{name}' not found in any loaded pack.\nRun `rails ai:skills:list` to see available skills.\n" unless resolved

        lines = []
        warning = @resolver.check_deprecated(name)
        lines << "WARNING: #{warning}" if warning

        lines << "INFO: Skill '#{name}' resolved from pack '#{resolved.pack}' (requested pack: '#{requested_pack}')." if requested_pack && resolved.pack != requested_pack

        lines << "# #{resolved.name} (from pack: #{resolved.pack})"
        lines << "# Path: #{resolved.path}"
        lines << ''
        lines << resolved.content
        lines.join("\n")
      end

      # @param path [String] manifest path that was not found
      # @return [String]
      def self.no_manifest_message(path)
        format(NO_MANIFEST_MESSAGE, path: path)
      end
    end
  end
end
