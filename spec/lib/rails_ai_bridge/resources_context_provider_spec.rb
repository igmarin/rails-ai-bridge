# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

RSpec.describe RailsAiBridge::Resources do
  let(:context) do
    {
      app_name: 'TestApp',
      generated_at: Time.now.iso8601,
      models: { 'User' => { name: 'User' } },
      stimulus: { controllers: [{ name: 'hello' }] }
    }
  end

  before do
    allow(RailsAiBridge::ContextProvider).to receive(:fetch).and_return(context)
    allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:models).and_return(context[:models])
    allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:stimulus).and_return(context[:stimulus])
  end

  describe 'context provider resources' do
    let(:simple_tool) { RailsAiBridge::Registry::ContextToolSpec.new(name: 'search', field: nil, arguments: nil) }
    let(:mapped_tool) { RailsAiBridge::Registry::ContextToolSpec.new(name: 'get_page', field: 'page', arguments: { limit: 10 }) }
    let(:provider) do
      RailsAiBridge::Registry::ContextProviderDefinition.new(
        type: 'mcp',
        endpoint: 'https://example.com/mcp',
        optional: true,
        tools: [simple_tool, mapped_tool]
      )
    end
    let(:manifest) do
      instance_double(RailsAiBridge::Registry::RegistryManifest, context_providers: { 'docs' => provider })
    end

    before do
      allow(described_class).to receive(:load_registry_manifest).and_return(manifest)
    end

    it 'includes context provider resources in resource_definitions' do
      allow(RailsAiBridge.configuration).to receive(:additional_resources).and_return({})
      defs = described_class.resource_definitions

      expect(defs).to have_key('rails://context-providers/docs')
      expect(defs['rails://context-providers/docs'][:context_provider_name]).to eq('docs')
    end

    it 'reads a context provider resource through handle_read' do
      rows = described_class.send(:handle_read, { uri: 'rails://context-providers/docs' })
      json = JSON.parse(rows.first[:text])

      expect(json['name']).to eq('docs')
      expect(json['type']).to eq('mcp')
      expect(json['endpoint']).to eq('https://example.com/mcp')
      expect(json['optional']).to be(true)
      expect(json['tools'].length).to eq(2)
      expect(json['tools'][0]).to eq({ 'name' => 'search' })
      expect(json['tools'][1]['field']).to eq('page')
      expect(json['tools'][1]['arguments']).to eq({ 'limit' => 10 })
    end

    it 'returns nil for an unknown context provider name' do
      result = described_class.send(:read_context_provider, 'unknown')
      expect(result).to be_nil
    end

    it 'returns nil for a context provider URI that does not match the pattern' do
      result = described_class.send(:read_context_provider_resource, 'rails://models/User')
      expect(result).to be_nil
    end

    it 'returns nil for a view URI that does not match the view pattern' do
      result = described_class.send(:read_view_template_resource, 'rails://models/User')
      expect(result).to be_nil
    end

    it 'returns nil for a stimulus URI that does not match the stimulus pattern' do
      result = described_class.send(:read_stimulus_template_resource, 'rails://models/User')
      expect(result).to be_nil
    end

    it 'returns nil for a model URI that does not match the model pattern' do
      result = described_class.send(:read_model_resource, 'rails://stimulus/hello')
      expect(result).to be_nil
    end
  end

  describe 'load_registry_manifest' do
    it 'returns nil when the manifest path does not exist' do
      allow(RailsAiBridge.configuration.registry).to receive(:registry_manifest_path)
        .and_return('/nonexistent/manifest.json')

      expect(described_class.send(:load_registry_manifest)).to be_nil
    end

    it 'returns nil when the manifest path is nil' do
      allow(RailsAiBridge.configuration.registry).to receive(:registry_manifest_path).and_return(nil)

      expect(described_class.send(:load_registry_manifest)).to be_nil
    end

    it 'returns nil and logs when the manifest has invalid JSON' do
      Dir.mktmpdir do |dir|
        manifest_path = File.join(dir, 'registry.json')
        File.write(manifest_path, '{ invalid json }')
        allow(RailsAiBridge.configuration.registry).to receive(:registry_manifest_path).and_return(manifest_path)
        logger = instance_double(ActiveSupport::Logger)
        allow(Rails).to receive(:logger).and_return(logger)
        allow(logger).to receive(:error)

        result = described_class.send(:load_registry_manifest)

        expect(result).to be_nil
        expect(logger).to have_received(:error) do |&block|
          expect(block.call).to include('Resource manifest load failed')
        end
      end
    end

    it 'returns nil without raising when Rails.logger is nil and manifest is invalid' do
      Dir.mktmpdir do |dir|
        manifest_path = File.join(dir, 'registry.json')
        File.write(manifest_path, '{ invalid json }')
        allow(RailsAiBridge.configuration.registry).to receive(:registry_manifest_path).and_return(manifest_path)
        allow(Rails).to receive(:logger).and_return(nil)

        expect { described_class.send(:load_registry_manifest) }.not_to raise_error
      end
    end
  end

  describe 'context_provider_resources with no manifest' do
    it 'returns empty hash when manifest is nil' do
      allow(described_class).to receive(:load_registry_manifest).and_return(nil)

      expect(described_class.send(:context_provider_resources)).to eq({})
    end
  end

  describe 'read_context_provider with no manifest' do
    it 'returns nil when manifest is nil' do
      allow(described_class).to receive(:load_registry_manifest).and_return(nil)

      expect(described_class.send(:read_context_provider, 'docs')).to be_nil
    end
  end

  describe 'sanitize_conventions_section' do
    it 'returns the section unchanged when it is not a Hash' do
      result = described_class.send(:sanitize_conventions_section, 'not-a-hash')

      expect(result).to eq('not-a-hash')
    end

    it 'returns the section unchanged when config_files is nil' do
      result = described_class.send(:sanitize_conventions_section, { architecture: ['mvc'] })

      expect(result).to eq({ architecture: ['mvc'] })
    end

    it 'filters secret-bearing config files when config_files is present' do
      section = {
        config_files: ['config/database.yml', '.env.production', 'config/routes.rb']
      }

      result = described_class.send(:sanitize_conventions_section, section)

      expect(result[:config_files]).to eq(['config/database.yml', 'config/routes.rb'])
    end
  end

  describe 'sanitize_context_section for non-conventions keys' do
    it 'returns the section unchanged for keys without a sanitizer' do
      section = { data: 'test' }

      result = described_class.send(:sanitize_context_section, :schema, section)

      expect(result).to eq(section)
    end
  end

  describe 'read_static_resource for unknown URI' do
    it 'returns nil for a URI not in resource_definitions' do
      allow(described_class).to receive(:resource_definitions).and_return({})

      expect(described_class.send(:read_static_resource, 'rails://unknown')).to be_nil
    end
  end

  describe 'handle_read raising for unknown resource' do
    it 'raises an error with the URI in the message' do
      allow(described_class).to receive(:resolve_resource_payload).and_return(nil)

      expect do
        described_class.send(:handle_read, { uri: 'rails://unknown' })
      end.to raise_error(RuntimeError, 'Unknown resource: rails://unknown')
    end
  end
end
