# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Metadata entry for a single skill inside a pack's tile manifest.
    #
    # @!attribute [r] path
    #   @return [String] relative path to the skill markdown file
    # @!attribute [r] description
    #   @return [String, nil] optional description; if nil, frontmatter is used
    # @!attribute [r] tags
    #   @return [Array<String>] optional classification tags
    SkillEntry = Data.define(:path, :description, :tags)

    # Metadata entry for an agent/workflow inside a pack's tile manifest.
    #
    # @!attribute [r] path
    #   @return [String] relative path to the agent markdown file
    # @!attribute [r] description
    #   @return [String, nil] optional description
    # @!attribute [r] depends_on
    #   @return [Array<String>] skill names this agent depends on
    AgentEntry = Data.define(:path, :description, :depends_on)

    # Deprecation redirect entry for a renamed or moved skill.
    #
    # @!attribute [r] moved_to
    #   @return [String] name of the skill this has been moved to
    # @!attribute [r] message
    #   @return [String] human-readable deprecation message
    # @!attribute [r] removed_in
    #   @return [String, nil] version in which this alias will be removed
    DeprecatedEntry = Data.define(:moved_to, :message, :removed_in) do
      # @return [Boolean]
      # :reek:NilCheck
      def removed_in? = !removed_in.nil?
    end

    # Immutable value object describing a pack's full catalog of skills and agents.
    #
    # @!attribute [r] name
    #   @return [String] unique pack name, e.g. "ruby-core-skills"
    # @!attribute [r] version
    #   @return [String] semantic version of the pack
    # @!attribute [r] summary
    #   @return [String, nil] optional human-readable pack description
    # @!attribute [r] depends_on
    #   @return [Array<String>] names of packs this tile depends on
    # @!attribute [r] skills
    #   @return [Hash{String => SkillEntry}]
    # @!attribute [r] agents
    #   @return [Hash{String => AgentEntry}]
    # @!attribute [r] deprecated_skills
    #   @return [Hash{String => DeprecatedEntry}]
    TileManifest = Data.define(:name, :version, :summary, :depends_on, :skills, :agents, :deprecated_skills) do
      # Builds a {TileManifest} from a parsed JSON hash.
      #
      # @param hash [Hash] parsed JSON object
      # @return [TileManifest]
      def self.from_json(hash)
        new(
          name: hash.fetch('name'),
          version: hash.fetch('version'),
          summary: hash['summary'],
          depends_on: hash.fetch('depends_on', []),
          skills: parse_skills(hash['skills'] || {}),
          agents: parse_agents(hash['agents'] || {}),
          deprecated_skills: parse_deprecated(hash['deprecated_skills'] || {})
        )
      end

      # Loads and parses a tile manifest from a JSON file on disk.
      #
      # @param path [String] path to the tile JSON file
      # @return [TileManifest]
      # @raise [ArgumentError] if the file does not exist or contains malformed JSON
      def self.from_file(path)
        raise ArgumentError, "Tile manifest not found at: #{path}" unless File.exist?(path)

        from_json(JSON.parse(File.read(path)))
      rescue JSON::ParserError => error
        raise ArgumentError, "Tile manifest at '#{path}' contains invalid JSON: #{error.message}"
      end

      # @api private
      def self.parse_skills(skills_hash)
        skills_hash.transform_values do |skill_data|
          SkillEntry.new(
            path: skill_data.fetch('path'),
            description: skill_data['description'],
            tags: skill_data.fetch('tags', [])
          )
        end
      end

      # @api private
      def self.parse_agents(agents_hash)
        agents_hash.transform_values do |agent_data|
          AgentEntry.new(
            path: agent_data.fetch('path'),
            description: agent_data['description'],
            depends_on: agent_data.fetch('depends_on', [])
          )
        end
      end

      # @api private
      def self.parse_deprecated(deprecated_hash)
        deprecated_hash.transform_values do |entry_data|
          DeprecatedEntry.new(
            moved_to: entry_data.fetch('moved_to'),
            message: entry_data.fetch('message'),
            removed_in: entry_data['removed_in']
          )
        end
      end

      private_class_method :parse_skills, :parse_agents, :parse_deprecated
    end
  end
end
