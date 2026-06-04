# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'rails_ai_bridge/registry/resolver'
require 'rails_ai_bridge/registry/tile_manifest'

RSpec.describe RailsAiBridge::Registry::Resolver do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  # Helper to create a temporary pack with files
  def create_temp_pack(name, skills: {}, agents: {}, deprecated_skills: {}, depends_on: [])
    pack_dir = File.join(temp_dir, name)
    FileUtils.mkdir_p(pack_dir)

    skills.each do |skill_name, content|
      skill_path = File.join(pack_dir, "skills/#{skill_name}.md")
      FileUtils.mkdir_p(File.dirname(skill_path))
      File.write(skill_path, content[:content])
    end

    agents.each do |agent_name, content|
      agent_path = File.join(pack_dir, "agents/#{agent_name}.md")
      FileUtils.mkdir_p(File.dirname(agent_path))
      File.write(agent_path, content[:content])
    end

    tile_skills = skills.transform_keys { |k| k.gsub('_', '-') }.transform_values do |content|
      RailsAiBridge::Registry::SkillEntry.new(
        path: "skills/#{content[:path]}.md",
        description: content[:description],
        tags: []
      )
    end

    tile_agents = agents.transform_keys { |k| k.gsub('_', '-') }.transform_values do |content|
      RailsAiBridge::Registry::AgentEntry.new(
        path: "agents/#{content[:path]}.md",
        description: content[:description],
        depends_on: content[:depends_on] || []
      )
    end

    tile = RailsAiBridge::Registry::TileManifest.new(
      name: name,
      version: '1.0.0',
      summary: "Summary of #{name}",
      depends_on: depends_on,
      skills: tile_skills,
      agents: tile_agents,
      deprecated_skills: deprecated_skills
    )

    { dir: pack_dir, tile: tile }
  end

  describe '#initialize' do
    it 'sorts packs by priority ascending' do
      pack1 = create_temp_pack('pack1', skills: { 'test_skill' => { path: 'test_skill', description: 'Test', content: 'Test' } })
      pack2 = create_temp_pack('pack2', skills: { 'test_skill' => { path: 'test_skill', description: 'Test', content: 'Test' } })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack1', tile: pack1[:tile], base_path: pack1[:dir], priority: 20),
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack2', tile: pack2[:tile], base_path: pack2[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      expect(resolver.active_packs.map(&:name)).to eq(%w[pack2 pack1])
    end

    it 'builds deprecated_index from packs' do
      deprecated_skills = {
        'old-skill' => RailsAiBridge::Registry::DeprecatedEntry.new(
          moved_to: 'new-skill',
          message: 'Use new-skill instead',
          removed_in: 'v2.0.0'
        )
      }
      pack = create_temp_pack('pack', skills: {}, deprecated_skills: deprecated_skills)

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      expect(resolver.check_deprecated('old-skill')).to include('deprecated')
    end
  end

  describe '#resolve_skill' do
    it 'resolves skill from highest priority pack' do
      core_pack = create_temp_pack('core', skills: { 'test_skill' => { path: 'test_skill', description: 'Core test', content: 'Core test' } })
      rails_pack = create_temp_pack('rails', skills: { 'test_skill' => { path: 'test_skill', description: 'Rails test', content: 'Rails test' } })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'core', tile: core_pack[:tile], base_path: core_pack[:dir], priority: 20),
        RailsAiBridge::Registry::LoadedPack.new(name: 'rails', tile: rails_pack[:tile], base_path: rails_pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      resolved = resolver.resolve_skill('test-skill')

      expect(resolved).not_to be_nil
      expect(resolved.content).to eq('Rails test')
      expect(resolved.pack).to eq('rails')
    end

    it 'returns nil for non-existent skill' do
      pack = create_temp_pack('pack', skills: {})

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      expect(resolver.resolve_skill('non-existent')).to be_nil
    end

    it 'handles deprecation redirect transparently' do
      deprecated_skills = {
        'old-skill' => RailsAiBridge::Registry::DeprecatedEntry.new(
          moved_to: 'new-skill',
          message: 'Use new-skill instead',
          removed_in: 'v2.0.0'
        )
      }
      pack = create_temp_pack('pack', skills: { 'new_skill' => { path: 'new_skill', description: 'New skill', content: 'New skill' } }, deprecated_skills: deprecated_skills)

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      resolved = resolver.resolve_skill('old-skill')

      expect(resolved).not_to be_nil
      expect(resolved.name).to eq('new-skill')
      expect(resolved.content).to eq('New skill')
    end

    it 'blocks path traversal attacks' do
      # Create a pack with a skill that tries to escape
      pack = create_temp_pack('pack', skills: {})

      # Manually create a malicious skill entry
      malicious_tile = RailsAiBridge::Registry::TileManifest.new(
        name: 'pack',
        version: '1.0.0',
        summary: 'Malicious pack',
        depends_on: [],
        skills: {
          'malicious' => RailsAiBridge::Registry::SkillEntry.new(
            path: '../../../etc/passwd',
            description: 'Malicious',
            tags: []
          )
        },
        agents: {},
        deprecated_skills: {}
      )

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: malicious_tile, base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      resolved = resolver.resolve_skill('malicious')

      expect(resolved).to be_nil
    end
  end

  describe '#resolve_agent' do
    it 'resolves agent from pack' do
      pack = create_temp_pack('pack', agents: { 'test_agent' => { path: 'test_agent', description: 'Test agent', depends_on: [], content: 'Test agent' } })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      resolved = resolver.resolve_agent('test-agent')

      expect(resolved).not_to be_nil
      expect(resolved.content).to eq('Test agent')
      expect(resolved.pack).to eq('pack')
    end

    it 'returns nil for non-existent agent' do
      pack = create_temp_pack('pack', agents: {})

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      expect(resolver.resolve_agent('non-existent')).to be_nil
    end
  end

  describe '#list_skills' do
    it 'lists all skills deduplicated by priority' do
      core_pack = create_temp_pack('core', skills: { 'test_skill' => { path: 'test_skill', description: 'Core test', content: 'Core test' } })
      rails_pack = create_temp_pack('rails', skills: { 'test_skill' => { path: 'test_skill', description: 'Rails test', content: 'Rails test' } })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'core', tile: core_pack[:tile], base_path: core_pack[:dir], priority: 20),
        RailsAiBridge::Registry::LoadedPack.new(name: 'rails', tile: rails_pack[:tile], base_path: rails_pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      skills = resolver.list_skills

      expect(skills.length).to eq(1)
      expect(skills.first.name).to eq('test-skill')
      expect(skills.first.description).to eq('Rails test')
      expect(skills.first.pack).to eq('rails')
    end

    it 'sorts skills alphabetically' do
      pack = create_temp_pack('pack', skills: {
                                'zebra_skill' => { path: 'zebra_skill', description: 'Zebra', content: 'Zebra' },
                                'alpha_skill' => { path: 'alpha_skill', description: 'Alpha', content: 'Alpha' }
                              })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      skills = resolver.list_skills

      expect(skills.map(&:name)).to eq(%w[alpha-skill zebra-skill])
    end
  end

  describe '#list_agents' do
    it 'lists all agents deduplicated by priority' do
      core_pack = create_temp_pack('core', agents: { 'test_agent' => { path: 'test_agent', description: 'Core agent', depends_on: [], content: 'Core agent' } })
      rails_pack = create_temp_pack('rails', agents: { 'test_agent' => { path: 'test_agent', description: 'Rails agent', depends_on: [], content: 'Rails agent' } })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'core', tile: core_pack[:tile], base_path: core_pack[:dir], priority: 20),
        RailsAiBridge::Registry::LoadedPack.new(name: 'rails', tile: rails_pack[:tile], base_path: rails_pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      agents = resolver.list_agents

      expect(agents.length).to eq(1)
      expect(agents.first.name).to eq('test-agent')
      expect(agents.first.description).to eq('Rails agent')
      expect(agents.first.pack).to eq('rails')
    end

    it 'sorts agents alphabetically' do
      pack = create_temp_pack('pack', agents: {
                                'zebra_agent' => { path: 'zebra_agent', description: 'Zebra', depends_on: [], content: 'Zebra' },
                                'alpha_agent' => { path: 'alpha_agent', description: 'Alpha', depends_on: [], content: 'Alpha' }
                              })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      agents = resolver.list_agents

      expect(agents.map(&:name)).to eq(%w[alpha-agent zebra-agent])
    end
  end

  describe '#validate_dependencies' do
    it 'warns when depends_on not satisfied' do
      pack = create_temp_pack('rails', depends_on: ['core'])

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'rails', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      warnings = resolver.validate_dependencies

      expect(warnings.length).to eq(1)
      expect(warnings.first).to include("depends on 'core', which is not loaded")
    end

    it 'passes when all deps loaded' do
      rails_pack = create_temp_pack('rails', depends_on: ['core'])
      core_pack = create_temp_pack('core')

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'rails', tile: rails_pack[:tile], base_path: rails_pack[:dir], priority: 10),
        RailsAiBridge::Registry::LoadedPack.new(name: 'core', tile: core_pack[:tile], base_path: core_pack[:dir], priority: 20)
      ]

      resolver = described_class.new(loaded_packs)
      warnings = resolver.validate_dependencies

      expect(warnings).to be_empty
    end
  end

  describe '#check_deprecated' do
    it 'returns warning for deprecated skill with removal version' do
      deprecated_skills = {
        'old-skill' => RailsAiBridge::Registry::DeprecatedEntry.new(
          moved_to: 'new-skill',
          message: 'Use new-skill instead',
          removed_in: 'v2.0.0'
        )
      }
      pack = create_temp_pack('pack', deprecated_skills: deprecated_skills)

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      warning = resolver.check_deprecated('old-skill')

      expect(warning).to include('deprecated')
      expect(warning).to include('Use new-skill instead')
      expect(warning).to include('v2.0.0')
    end

    it 'returns warning for deprecated skill without removal version' do
      deprecated_skills = {
        'old-skill' => RailsAiBridge::Registry::DeprecatedEntry.new(
          moved_to: 'new-skill',
          message: 'Use new-skill instead',
          removed_in: nil
        )
      }
      pack = create_temp_pack('pack', deprecated_skills: deprecated_skills)

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      warning = resolver.check_deprecated('old-skill')

      expect(warning).to include('deprecated')
      expect(warning).to include('Use new-skill instead')
      expect(warning).not_to include('will be removed')
    end

    it 'returns nil for non-deprecated skill' do
      pack = create_temp_pack('pack')

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      expect(resolver.check_deprecated('some-skill')).to be_nil
    end
  end

  describe '#active_packs' do
    it 'returns loaded packs sorted by priority' do
      pack1 = create_temp_pack('pack1')
      pack2 = create_temp_pack('pack2')

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack1', tile: pack1[:tile], base_path: pack1[:dir], priority: 20),
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack2', tile: pack2[:tile], base_path: pack2[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      expect(resolver.active_packs.map(&:name)).to eq(%w[pack2 pack1])
    end
  end

  describe '#get_agent_dependencies' do
    it 'returns dependencies for agent' do
      pack = create_temp_pack('pack', agents: {
                                'test_agent' => { path: 'test_agent', description: 'Test', depends_on: %w[skill1 skill2], content: 'Test' }
                              })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      deps = resolver.get_agent_dependencies('test-agent')

      expect(deps).to eq(%w[skill1 skill2])
    end

    it 'returns nil for non-existent agent' do
      pack = create_temp_pack('pack', agents: {})

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      expect(resolver.get_agent_dependencies('non-existent')).to be_nil
    end

    it 'returns empty array for agent with no dependencies' do
      pack = create_temp_pack('pack', agents: {
                                'test_agent' => { path: 'test_agent', description: 'Test', depends_on: [], content: 'Test' }
                              })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      deps = resolver.get_agent_dependencies('test-agent')

      expect(deps).to eq([])
    end
  end

  describe 'edge cases' do
    it 'handles empty packs list' do
      resolver = described_class.new([])
      expect(resolver.active_packs).to eq([])
      expect(resolver.list_skills).to eq([])
      expect(resolver.list_agents).to eq([])
    end

    it 'handles pack with no skills or agents' do
      pack = create_temp_pack('pack', skills: {}, agents: {})

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      expect(resolver.list_skills).to eq([])
      expect(resolver.list_agents).to eq([])
    end

    it 'handles skill with missing description' do
      pack = create_temp_pack('pack', skills: {
                                'test_skill' => { path: 'test_skill', content: 'Test' }
                              })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      skills = resolver.list_skills

      expect(skills.length).to eq(1)
      expect(skills.first.description).to eq('No description provided.')
    end

    it 'handles agent with missing description' do
      pack = create_temp_pack('pack', agents: {
                                'test_agent' => { path: 'test_agent', content: 'Test' }
                              })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      agents = resolver.list_agents

      expect(agents.length).to eq(1)
      expect(agents.first.description).to eq('No description provided.')
    end

    it 'handles skill file read errors' do
      pack = create_temp_pack('pack', skills: {
                                'test_skill' => { path: 'nonexistent/file', description: 'Test', content: 'Test' }
                              })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      # Should return nil when file doesn't exist
      resolved = resolver.resolve_skill('test-skill')
      expect(resolved).to be_nil
    end

    it 'handles agent file read errors' do
      pack = create_temp_pack('pack', agents: {
                                'test_agent' => { path: 'nonexistent/file', description: 'Test', content: 'Test' }
                              })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      # Should return nil when file doesn't exist
      resolved = resolver.resolve_agent('test-agent')
      expect(resolved).to be_nil
    end

    it 'handles agent path traversal attack attempts' do
      pack = create_temp_pack('pack', agents: {
                                'test_agent' => { path: '../../../etc/passwd', description: 'Test', content: 'Test' }
                              })

      loaded_packs = [
        RailsAiBridge::Registry::LoadedPack.new(name: 'pack', tile: pack[:tile], base_path: pack[:dir], priority: 10)
      ]

      resolver = described_class.new(loaded_packs)
      # Should return nil when path tries to escape base path
      resolved = resolver.resolve_agent('test-agent')
      expect(resolved).to be_nil
    end
  end
end
