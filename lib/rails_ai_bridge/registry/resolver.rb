# frozen_string_literal: true

require 'pathname'

module RailsAiBridge
  module Registry
    # A loaded pack representing a registered repository.
    #
    # @!attribute [r] name
    #   @return [String] name of the pack
    # @!attribute [r] tile
    #   @return [TileManifest] deserialized tile manifest
    # @!attribute [r] base_path
    #   @return [String] local filesystem path where the pack is located
    # @!attribute [r] priority
    #   @return [Integer] priority level (lower value is higher priority)
    LoadedPack = Data.define(:name, :tile, :base_path, :priority)

    # A resolved skill or agent, containing its content and metadata.
    #
    # @!attribute [r] name
    #   @return [String] name of the resolved skill/agent
    # @!attribute [r] pack
    #   @return [String] pack from which it was resolved
    # @!attribute [r] path
    #   @return [String] absolute filesystem path to the markdown file
    # @!attribute [r] content
    #   @return [String] complete text content of the markdown file
    ResolvedSkill = Data.define(:name, :pack, :path, :content)

    # Summary of a skill or agent for catalogs.
    #
    # @!attribute [r] name
    #   @return [String] unique name of the skill/agent
    # @!attribute [r] pack
    #   @return [String] source pack name
    # @!attribute [r] description
    #   @return [String] human-readable description
    SkillSummary = Data.define(:name, :pack, :description)

    # Core resolver that aggregates active packs and resolves queries.
    #
    # Provides priority-based resolution of skills and agents, handles deprecation
    # redirects, validates dependencies, and guards against path traversal attacks.
    class Resolver
      # Builds a new RegistryResolver from a list of loaded packs.
      #
      # Packs are sorted by priority ascending (highest priority first).
      # Deprecated skills are indexed in reverse priority order so higher
      # priority deprecations overwrite lower priority ones.
      #
      # @param loaded_packs [Array<LoadedPack>] list of loaded packs
      def initialize(loaded_packs)
        # Sort active packs by priority ascending (highest priority first)
        @active_packs = loaded_packs.sort_by(&:priority)

        # Gather deprecated skills in reverse order so higher priority overwrites
        @deprecated_index = build_deprecated_index
      end

      # Resolves a skill by name, handling priority tiers and deprecation redirects.
      #
      # @param name [String] name of the skill to resolve
      # @return [ResolvedSkill, nil] resolved skill or nil if not found
      def resolve_skill(name)
        # Handle deprecation redirects transparently
        target_name = if (dep = @deprecated_index[name])
                        dep.moved_to
                      else
                        name
                      end

        @active_packs.each do |pack|
          entry = pack.tile.skills[target_name]
          next unless entry

          file_path = File.join(pack.base_path, entry.path)
          next unless descendant?(pack.base_path, file_path)

          content = File.read(file_path)
          return ResolvedSkill.new(
            name: target_name,
            pack: pack.name,
            path: file_path,
            content: content
          )
        end

        nil
      end

      # Resolves an agent by name, handling priority tiers.
      #
      # @param name [String] name of the agent to resolve
      # @return [ResolvedSkill, nil] resolved agent or nil if not found
      def resolve_agent(name)
        @active_packs.each do |pack|
          entry = pack.tile.agents[name]
          next unless entry

          file_path = File.join(pack.base_path, entry.path)
          next unless descendant?(pack.base_path, file_path)

          content = File.read(file_path)
          return ResolvedSkill.new(
            name: name,
            pack: pack.name,
            path: file_path,
            content: content
          )
        end

        nil
      end

      # Returns a list of all unique skills across active packs, deduplicated by priority.
      #
      # Skills from higher priority packs overwrite skills from lower priority packs.
      # Results are sorted alphabetically by skill name.
      #
      # @return [Array<SkillSummary>] list of skill summaries
      def list_skills
        skill_map = {}

        # Iterate in reverse priority order (lowest priority first)
        # so higher priority overwrites them in the map
        sorted_reverse = @active_packs.sort_by { |p| -p.priority }

        sorted_reverse.each do |pack|
          pack.tile.skills.each do |skill_name, entry|
            description = entry.description || 'No description provided.'
            skill_map[skill_name] = SkillSummary.new(
              name: skill_name,
              pack: pack.name,
              description: description
            )
          end
        end

        skill_map.values.sort_by(&:name)
      end

      # Returns a list of all unique agents across active packs, deduplicated by priority.
      #
      # Agents from higher priority packs overwrite agents from lower priority packs.
      # Results are sorted alphabetically by agent name.
      #
      # @return [Array<SkillSummary>] list of agent summaries
      def list_agents
        agent_map = {}

        sorted_reverse = @active_packs.sort_by { |p| -p.priority }

        sorted_reverse.each do |pack|
          pack.tile.agents.each do |agent_name, entry|
            description = entry.description || 'No description provided.'
            agent_map[agent_name] = SkillSummary.new(
              name: agent_name,
              pack: pack.name,
              description: description
            )
          end
        end

        agent_map.values.sort_by(&:name)
      end

      # Validates that all pack dependencies are satisfied among active packs.
      #
      # @return [Array<String>] list of warning strings for missing dependencies
      def validate_dependencies
        warnings = []
        loaded_names = @active_packs.to_set(&:name)

        @active_packs.each do |pack|
          pack.tile.depends_on.each do |dep|
            warnings << "Pack '#{pack.name}' depends on '#{dep}', which is not loaded." unless loaded_names.include?(dep)
          end
        end

        warnings
      end

      # Check if a skill name is deprecated, returning the warning message if so.
      #
      # @param name [String] name of the skill to check
      # @return [String, nil] warning message if deprecated, nil otherwise
      def check_deprecated(name)
        dep = @deprecated_index[name]
        return nil unless dep

        if dep.removed_in?
          "Skill '#{name}' is deprecated: #{dep.message}. It will be removed in version #{dep.removed_in}."
        else
          "Skill '#{name}' is deprecated: #{dep.message}."
        end
      end

      # Direct access to loaded packs (useful for tool lists/status).
      #
      # @return [Array<LoadedPack>] list of loaded packs sorted by priority
      attr_reader :active_packs

      # Gets dependency list for a specific agent.
      #
      # @param name [String] name of the agent
      # @return [Array<String>, nil] list of skill dependencies or nil if agent not found
      def get_agent_dependencies(name)
        @active_packs.each do |pack|
          entry = pack.tile.agents[name]
          return entry.depends_on.dup if entry
        end

        nil
      end

      private

      # Builds the deprecated skills index from all packs.
      #
      # Packs are processed in reverse priority order so higher priority
      # deprecations overwrite lower priority ones.
      #
      # @return [Hash{String => DeprecatedEntry}] deprecated skills index
      def build_deprecated_index
        index = {}

        sorted_reverse = @active_packs.sort_by { |p| -p.priority }

        sorted_reverse.each do |pack|
          pack.tile.deprecated_skills.each do |old_name, entry|
            index[old_name] = entry
          end
        end

        index
      end

      # Checks if a path is a descendant of a base path (path traversal guard).
      #
      # Uses realpath to resolve symlinks and canonicalize paths before comparison.
      # Enforces a path-separator boundary to prevent false positives from sibling directories.
      #
      # @param base [String] base directory path
      # @param path [String] path to check
      # @return [Boolean] true if path is a descendant of base
      def descendant?(base, path)
        base_canon = Pathname.new(base).realpath
        path_canon = Pathname.new(path).realpath
      rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR
        false
      else
        # Ensure path_canon starts with base_canon followed by a separator or is exactly equal
        base_str = base_canon.to_s
        path_str = path_canon.to_s
        path_str == base_str || path_str.start_with?(base_str + File::SEPARATOR)
      end
    end
  end
end
