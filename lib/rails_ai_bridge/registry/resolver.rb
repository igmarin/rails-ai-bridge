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

        # Pre-compute the reverse order once; used by list_skills, list_agents,
        # and build_deprecated_index so they don't each sort independently.
        @active_packs_reverse = @active_packs.reverse

        # Gather deprecated skills in reverse order so higher priority overwrites
        @deprecated_index = build_deprecated_index
      end

      # Resolves a skill by name, handling priority tiers and deprecation redirects.
      #
      # @param name [String] name of the skill to resolve
      # @return [ResolvedSkill, nil] resolved skill or nil if not found
      def resolve_skill(name)
        # Handle deprecation redirects transparently
        target_name = (dep = @deprecated_index[name]) ? dep.moved_to : name
        resolve_entry(target_name, collection: :skills)
      end

      # Resolves an agent by name, handling priority tiers.
      #
      # @param name [String] name of the agent to resolve
      # @return [ResolvedSkill, nil] resolved agent or nil if not found
      def resolve_agent(name)
        resolve_entry(name, collection: :agents)
      end

      # Returns a list of all unique skills across active packs, deduplicated by priority.
      #
      # Skills from higher priority packs overwrite skills from lower priority packs.
      # Results are sorted alphabetically by skill name.
      #
      # @return [Array<SkillSummary>] list of skill summaries
      def list_skills
        build_summary_map(:skills).values.sort_by(&:name)
      end

      # Returns a list of all unique agents across active packs, deduplicated by priority.
      #
      # Agents from higher priority packs overwrite agents from lower priority packs.
      # Results are sorted alphabetically by agent name.
      #
      # @return [Array<SkillSummary>] list of agent summaries
      def list_agents
        build_summary_map(:agents).values.sort_by(&:name)
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

      # Resolves a named entry (skill or agent) from active packs in priority order.
      #
      # Iterates @active_packs (already sorted by ascending priority) and returns
      # the first entry whose file passes the descendant guard and can be read.
      #
      # @param name [String] entry name
      # @param collection [Symbol] :skills or :agents
      # @return [ResolvedSkill, nil]
      def resolve_entry(name, collection:)
        @active_packs.each do |pack|
          entry = pack.tile.public_send(collection)[name]
          next unless entry

          file_path = File.join(pack.base_path, entry.path)
          next unless descendant?(pack.base_path, file_path)

          begin
            content = File.read(file_path)
          rescue SystemCallError
            next
          end

          return ResolvedSkill.new(name: name, pack: pack.name, path: file_path, content: content)
        end

        nil
      end

      # Builds a name → SkillSummary map for skills or agents, deduplicated by
      # priority (higher priority packs overwrite lower priority ones).
      #
      # Uses @active_packs_reverse so low-priority entries are written first and
      # high-priority entries overwrite them — no repeated sort needed.
      #
      # @param collection [Symbol] :skills or :agents
      # @return [Hash{String => SkillSummary}]
      def build_summary_map(collection)
        map = {}
        @active_packs_reverse.each do |pack|
          pack.tile.public_send(collection).each do |entry_name, entry|
            map[entry_name] = SkillSummary.new(
              name: entry_name,
              pack: pack.name,
              description: entry.description || 'No description provided.'
            )
          end
        end
        map
      end

      # Builds the deprecated skills index from all packs.
      #
      # Uses @active_packs_reverse so higher priority deprecations overwrite
      # lower priority ones without an additional sort.
      #
      # @return [Hash{String => DeprecatedEntry}] deprecated skills index
      def build_deprecated_index
        index = {}
        @active_packs_reverse.each do |pack|
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
        # ENOENT  — file was deleted between resolution and the descendant check; skip it.
        # EACCES  — permission denied; treat as outside the base to fail closed.
        # ENOTDIR — a path component is not a directory (e.g. a symlink loop); fail closed.
        # All three are benign from a security perspective: returning false causes the
        # caller to skip the entry, which is the safest outcome in every case.
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
