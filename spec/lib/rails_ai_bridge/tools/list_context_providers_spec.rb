# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/registry/context_provider_definition'
require 'rails_ai_bridge/registry/context_tool_spec'

RSpec.describe RailsAiBridge::Tools::ListContextProviders do
  let(:response) { described_class.call(**params) }
  let(:content)  { response.content.first[:text] }
  let(:params)   { {} }

  def build_provider(type: 'mcp', endpoint: 'https://example.com/mcp', optional: false, tools: [])
    RailsAiBridge::Registry::ContextProviderDefinition.new(
      type: type,
      endpoint: endpoint,
      optional: optional,
      tools: tools
    )
  end

  def simple_tool(name)
    RailsAiBridge::Registry::ContextToolSpec.new(name: name, field: nil, arguments: nil)
  end

  def mapped_tool(name:, field:, arguments: nil)
    RailsAiBridge::Registry::ContextToolSpec.new(name: name, field: field, arguments: arguments)
  end

  # ── setup message (no manifest) ────────────────────────────────────────────

  context 'when no registry manifest is configured' do
    before do
      allow(described_class).to receive_messages(
        load_manifest: nil,
        manifest_path: 'config/rails_ai_bridge/registry.json'
      )
    end

    it 'mentions registry manifest' do
      expect(content).to include('registry manifest')
    end

    it 'mentions the manifest path' do
      expect(content).to include('config/rails_ai_bridge/registry.json')
    end

    it 'includes a quick-start JSON snippet' do
      expect(content).to include('"version"')
    end
  end

  # ── context providers present ──────────────────────────────────────────────

  context 'when context providers are declared' do
    let(:providers) do
      {
        'docs-server' => build_provider(
          type: 'mcp',
          endpoint: 'https://docs.example.com/mcp',
          optional: false,
          tools: [simple_tool('search_docs'), mapped_tool(name: 'get_page', field: 'page_content')]
        ),
        'wiki-server' => build_provider(
          type: 'mcp',
          endpoint: 'https://wiki.example.com/mcp',
          optional: true,
          tools: [simple_tool('search_wiki')]
        )
      }
    end
    let(:manifest) do
      instance_double(RailsAiBridge::Registry::RegistryManifest, context_providers: providers)
    end

    before { allow(described_class).to receive(:load_manifest).and_return(manifest) }

    it 'returns a markdown header' do
      expect(content).to include('# Context Providers')
    end

    it 'includes the total count' do
      expect(content).to include('(2)')
    end

    it 'lists each provider name' do
      expect(content).to include('docs-server')
      expect(content).to include('wiki-server')
    end

    it 'shows the type for each provider' do
      expect(content).to include('mcp')
    end

    it 'shows the endpoint for each provider' do
      expect(content).to include('https://docs.example.com/mcp')
      expect(content).to include('https://wiki.example.com/mcp')
    end

    it 'shows the optional flag' do
      expect(content).to include('yes')
      expect(content).to include('no')
    end

    it 'lists simple tool specs by name' do
      expect(content).to include('search_docs')
      expect(content).to include('search_wiki')
    end

    it 'lists mapped tool specs with field routing' do
      expect(content).to include('get_page → page_content')
    end
  end

  # ── no context providers (empty) ───────────────────────────────────────────

  context 'when the manifest has no context providers' do
    let(:manifest) do
      instance_double(RailsAiBridge::Registry::RegistryManifest, context_providers: {})
    end

    before { allow(described_class).to receive(:load_manifest).and_return(manifest) }

    it 'returns an empty message' do
      expect(content).to include('No context providers')
    end
  end

  # ── response shape ─────────────────────────────────────────────────────────

  context 'when returning the MCP response for declared providers' do
    let(:providers) { { 'docs-server' => build_provider(tools: [simple_tool('search_docs')]) } }
    let(:manifest) do
      instance_double(RailsAiBridge::Registry::RegistryManifest, context_providers: providers)
    end

    before { allow(described_class).to receive(:load_manifest).and_return(manifest) }

    it 'returns an MCP::Tool::Response' do
      expect(response).to be_a(MCP::Tool::Response)
    end

    it 'returns content with a text entry' do
      expect(response.content).to be_a(Array)
      expect(response.content.first[:type]).to eq('text')
      expect(response.content.first[:text]).to be_a(String)
    end
  end
end
