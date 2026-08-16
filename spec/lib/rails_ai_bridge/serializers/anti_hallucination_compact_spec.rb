# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'compact anti-hallucination block' do
  subject(:output) { serializer_class.new(context).call }

  let(:signature) { '[ASSUMPTION]' }
  let(:context) do
    {
      app_name: 'App',
      rails_version: '8.0',
      ruby_version: '3.4',
      generated_at: Time.now.iso8601,
      schema: { adapter: 'postgresql', total_tables: 2, tables: {} },
      models: { 'User' => { associations: [], validations: [], table_name: 'users' } },
      routes: { total_routes: 4, by_controller: {} },
      gems: {},
      conventions: {},
      tests: { framework: 'rspec' }
    }
  end

  around do |example|
    original_mode = RailsAiBridge.configuration.context_mode
    original_flag = RailsAiBridge.configuration.anti_hallucination_rules
    RailsAiBridge.configuration.context_mode = :compact
    example.run
  ensure
    RailsAiBridge.configuration.context_mode = original_mode
    RailsAiBridge.configuration.anti_hallucination_rules = original_flag
  end

  shared_examples 'includes the shared anti-hallucination block' do
    it 'includes the block when the flag is on' do
      RailsAiBridge.configuration.anti_hallucination_rules = true
      expect(output).to include(signature)
      expect(output).to include('Empty tool output is information')
      expect(output.scan(signature).size).to eq(1)
    end

    it 'omits the block when the flag is off' do
      RailsAiBridge.configuration.anti_hallucination_rules = false
      expect(output).not_to include(signature)
      expect(output).not_to include('## Anti-hallucination')
    end
  end

  describe 'Claude compact CLAUDE.md' do
    let(:serializer_class) { RailsAiBridge::Serializers::Providers::ClaudeSerializer }

    it_behaves_like 'includes the shared anti-hallucination block'
  end

  describe 'Gemini compact GEMINI.md' do
    let(:serializer_class) { RailsAiBridge::Serializers::Providers::GeminiSerializer }

    it_behaves_like 'includes the shared anti-hallucination block'
  end

  describe 'Copilot compact instructions' do
    let(:serializer_class) { RailsAiBridge::Serializers::Providers::CopilotSerializer }

    it_behaves_like 'includes the shared anti-hallucination block'
  end

  describe 'Codex compact AGENTS.md' do
    let(:serializer_class) { RailsAiBridge::Serializers::Providers::CodexSerializer }

    it_behaves_like 'includes the shared anti-hallucination block'
  end

  describe 'Cursor compact .cursorrules' do
    let(:serializer_class) { RailsAiBridge::Serializers::Providers::RulesSerializer }

    it_behaves_like 'includes the shared anti-hallucination block'
  end

  describe 'Cursor compact rails-engineering.mdc' do
    it 'includes the block when the flag is on' do
      RailsAiBridge.configuration.anti_hallucination_rules = true
      Dir.mktmpdir do |dir|
        RailsAiBridge::Serializers::Providers::CursorRulesSerializer.new(context).call(dir)
        eng = File.read(File.join(dir, '.cursor', 'rules', 'rails-engineering.mdc'))
        expect(eng).to include(signature)
        expect(eng).to include('Empty tool output is information')
        expect(eng.scan(signature).size).to eq(1)
      end
    end

    it 'omits the block when the flag is off' do
      RailsAiBridge.configuration.anti_hallucination_rules = false
      Dir.mktmpdir do |dir|
        RailsAiBridge::Serializers::Providers::CursorRulesSerializer.new(context).call(dir)
        eng = File.read(File.join(dir, '.cursor', 'rules', 'rails-engineering.mdc'))
        expect(eng).not_to include(signature)
        expect(eng).not_to include('## Anti-hallucination')
      end
    end
  end
end
