# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

# Characterization specs that pin the MCP resource list and template
# behavior. Resources are static data that AI clients read directly via
# the resources/read and resources/list JSON-RPC methods.
#
# These specs pin:
#   - MCP::Resource construction (uri, name, description, mime_type)
#   - MCP::ResourceTemplate construction (uri_template, name, description, mime_type)
#   - The full set of static resource URIs
#   - Resource read handler registration
#   - Resource read response format (JSON pretty-printed text)
RSpec.describe 'MCP resource lists (SDK 1.3.0)' do
  before do
    allow(RailsAiBridge::ContextProvider).to receive(:fetch).and_return(
      app_name: 'TestApp',
      generated_at: Time.now.iso8601,
      models: { 'User' => { name: 'User' } },
      stimulus: { controllers: [{ name: 'hello' }] }
    )
    allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:models).and_return({ 'User' => { name: 'User' } })
    allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:stimulus)
                                                                    .and_return({ controllers: [{ name: 'hello' }] })
    allow(RailsAiBridge.configuration).to receive(:additional_resources).and_return({})
    stub_const('RailsAiBridge::ViewFileAnalyzer', Module.new do
      def self.call(*_args)
        { test: 'data' }
      end
    end)
  end

  # ---- Resource construction ----

  describe 'MCP::Resource objects' do
    it 'builds an array of MCP::Resource instances' do
      resources = RailsAiBridge::Resources.build_resources

      expect(resources).to be_an(Array)
      expect(resources).to all(be_a(MCP::Resource))
    end

    it 'includes 13 static resources' do
      resources = RailsAiBridge::Resources.build_resources

      expect(resources.size).to eq(13)
    end

    it 'all resources have application/json mime type' do
      resources = RailsAiBridge::Resources.build_resources

      resources.each do |resource|
        expect(resource.mime_type).to eq('application/json')
      end
    end

    it 'all resources have a uri, name, and description' do
      resources = RailsAiBridge::Resources.build_resources

      resources.each do |resource|
        expect(resource.uri).to be_present
        expect(resource.name).to be_present
        expect(resource.description).to be_present
      end
    end

    it 'includes the bridge meta resource' do
      resources = RailsAiBridge::Resources.build_resources
      meta = resources.find { |r| r.uri == 'rails://bridge/meta' }

      expect(meta).not_to be_nil
      expect(meta.name).to eq('Bridge Metadata')
    end

    it 'includes the schema resource' do
      resources = RailsAiBridge::Resources.build_resources

      expect(resources.map(&:uri)).to include('rails://schema')
    end

    it 'includes the semantic analysis resource' do
      resources = RailsAiBridge::Resources.build_resources

      expect(resources.map(&:uri)).to include('rails://semantic/analysis')
    end
  end

  # ---- Resource template construction ----

  describe 'MCP::ResourceTemplate objects' do
    it 'builds an array of MCP::ResourceTemplate instances' do
      templates = RailsAiBridge::Resources.build_templates

      expect(templates).to be_an(Array)
      expect(templates).to all(be_a(MCP::ResourceTemplate))
    end

    it 'includes 4 resource templates' do
      templates = RailsAiBridge::Resources.build_templates

      expect(templates.size).to eq(4)
    end

    it 'includes model, view, stimulus, and context-provider templates' do
      templates = RailsAiBridge::Resources.build_templates
      uris = templates.map(&:uri_template)

      expect(uris).to include('rails://models/{name}')
      expect(uris).to include('rails://views/{path}')
      expect(uris).to include('rails://stimulus/{name}')
      expect(uris).to include('rails://context-providers/{name}')
    end

    it 'all templates have application/json mime type' do
      templates = RailsAiBridge::Resources.build_templates

      templates.each do |template|
        expect(template.mime_type).to eq('application/json')
      end
    end
  end

  # ---- Resource read handler ----

  describe 'resource read handler registration' do
    it 'registers a resources_read_handler on the MCP server' do
      mcp_server = double('MCP::Server')
      allow(mcp_server).to receive(:resources_read_handler).and_yield(uri: 'rails://bridge/meta')

      RailsAiBridge::Resources.register(mcp_server)

      expect(mcp_server).to have_received(:resources_read_handler)
    end
  end

  # ---- Resource read response format ----

  describe 'resource read response format' do
    it 'returns a JSON pretty-printed text payload' do
      result = RailsAiBridge::Resources.send(:json_resource, 'rails://test', { key: 'value' })

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first[:uri]).to eq('rails://test')
      expect(result.first[:mime_type]).to eq('application/json')
      expect(result.first[:text]).to include('"key": "value"')
    end

    it 'handles nil payload as null' do
      result = RailsAiBridge::Resources.send(:json_resource, 'rails://test', nil)

      expect(result.first[:text]).to eq('null')
    end
  end

  # ---- Static resource URIs ----

  describe 'static resource URI set' do
    it 'includes all expected URIs' do
      definitions = RailsAiBridge::Resources.resource_definitions
      uris = definitions.keys

      expected_uris = %w[
        rails://bridge/meta
        rails://schema
        rails://routes
        rails://conventions
        rails://gems
        rails://controllers
        rails://config
        rails://tests
        rails://migrations
        rails://engines
        rails://views
        rails://stimulus
        rails://semantic/analysis
      ]

      expect(uris).to include(*expected_uris)
    end
  end

  # ---- Templated resource resolution ----

  describe 'templated resource resolution' do
    it 'resolves model resources by name' do
      payload = RailsAiBridge::Resources.send(:resolve_resource_payload, 'rails://models/User')

      expect(payload).to eq({ name: 'User' })
    end

    it 'resolves URL-encoded model names' do
      allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:models)
                                                                      .and_return({ 'User::Profile' => { name: 'User::Profile' } })

      payload = RailsAiBridge::Resources.send(:resolve_resource_payload, 'rails://models/User%3A%3AProfile')

      expect(payload).to eq({ name: 'User::Profile' })
    end

    it 'returns an error hash for missing models' do
      payload = RailsAiBridge::Resources.send(:resolve_resource_payload, 'rails://models/NonExistent')

      expect(payload).to eq({ error: "Model 'NonExistent' not found" })
    end

    it 'resolves stimulus controllers case-insensitively' do
      payload = RailsAiBridge::Resources.send(:resolve_resource_payload, 'rails://stimulus/HELLO')

      expect(payload).to eq({ name: 'hello' })
    end

    it 'returns nil for unknown URIs' do
      payload = RailsAiBridge::Resources.send(:resolve_resource_payload, 'rails://unknown')

      expect(payload).to be_nil
    end
  end

  # ---- Bridge metadata resource ----

  describe 'bridge metadata resource' do
    it 'includes bridge version and configuration' do
      metadata = RailsAiBridge::Resources.send(:bridge_metadata)

      expect(metadata[:bridge_version]).to eq(RailsAiBridge::VERSION)
      expect(metadata[:server_name]).to eq(RailsAiBridge.configuration.server_name)
      expect(metadata[:app_name]).to eq('TestApp')
      expect(metadata[:available_resources]).to include('rails://bridge/meta')
    end

    it 'lists available tools sorted by name' do
      metadata = RailsAiBridge::Resources.send(:bridge_metadata)

      expect(metadata[:available_tools]).to be_an(Array)
      expect(metadata[:available_tools]).to eq(metadata[:available_tools].sort)
    end

    it 'lists available resources sorted by URI' do
      metadata = RailsAiBridge::Resources.send(:bridge_metadata)

      expect(metadata[:available_resources]).to eq(metadata[:available_resources].sort)
    end
  end

  # ---- Additional resources merge ----

  describe 'additional resources merge' do
    it 'merges user-defined resources with static resources' do
      additional = { 'custom://test' => { name: 'Test', description: 'Custom', mime_type: 'application/json' } }
      allow(RailsAiBridge.configuration).to receive(:additional_resources).and_return(additional)

      definitions = RailsAiBridge::Resources.resource_definitions

      expect(definitions).to include('custom://test')
      expect(definitions).to include('rails://bridge/meta')
    end
  end
end
