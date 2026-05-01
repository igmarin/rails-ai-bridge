# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Resources do
  let(:context) do
    {
      app_name: 'TestApp',
      generated_at: Time.now.iso8601,
      models: { 'User' => { name: 'User' } },
      stimulus: { controllers: [{ name: 'hello' }, { name: 'user' }] }
    }
  end

  before do
    allow(RailsAiBridge::ContextProvider).to receive(:fetch).and_return(context)
    allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:models).and_return(context[:models])
    allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:stimulus).and_return(context[:stimulus])
    allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:conventions).and_return(context[:conventions])

    # Stub ViewFileAnalyzer as a module with call method
    view_analyzer = Module.new do
      def self.call(*_args)
        { test: 'data' }
      end
    end
    stub_const('RailsAiBridge::ViewFileAnalyzer', view_analyzer)
  end

  describe '.resource_definitions' do
    it 'returns STATIC_RESOURCES merged with additional_resources' do
      additional = { 'custom://test' => { name: 'Test' } }
      allow(RailsAiBridge.configuration).to receive(:additional_resources).and_return(additional)

      result = described_class.resource_definitions

      expect(result).to include('rails://bridge/meta')
      expect(result).to include('custom://test')
      expect(result['rails://bridge/meta'][:name]).to eq('Bridge Metadata')
    end
  end

  describe '.build_resources' do
    it 'creates MCP::Resource objects for all definitions' do
      allow(RailsAiBridge.configuration).to receive(:additional_resources).and_return({})

      resources = described_class.build_resources

      expect(resources).to be_an(Array)
      expect(resources.size).to eq(12) # 11 static + bridge meta

      meta_resource = resources.find { |r| r.uri == 'rails://bridge/meta' }
      expect(meta_resource.name).to eq('Bridge Metadata')
      expect(meta_resource.mime_type).to eq('application/json')
    end
  end

  describe '.build_templates' do
    it 'creates MCP::ResourceTemplate objects' do
      templates = described_class.build_templates

      expect(templates).to be_an(Array)
      expect(templates.size).to eq(3)

      model_template = templates.find { |t| t.uri_template == 'rails://models/{name}' }
      expect(model_template.name).to eq('Model Details')
      expect(model_template.mime_type).to eq('application/json')
    end
  end

  describe 'private method behaviors (characterization)' do
    describe 'resolve_resource_payload' do
      it 'resolves static resources' do
        payload = described_class.send(:resolve_resource_payload, 'rails://bridge/meta')
        expect(payload).to be_a(Hash)
        expect(payload[:bridge_version]).to eq(RailsAiBridge::VERSION)
      end

      it 'resolves model template resources' do
        payload = described_class.send(:resolve_resource_payload, 'rails://models/User')
        expect(payload).to eq({ name: 'User' })
      end

      it 'resolves stimulus template resources' do
        payload = described_class.send(:resolve_resource_payload, 'rails://stimulus/hello')
        expect(payload).to eq({ name: 'hello' })
      end

      it 'sanitizes secret-bearing config paths from the conventions resource' do
        conventions = {
          architecture: ['mvc'],
          config_files: [
            'config/database.yml',
            '.env.production',
            'config/credentials/production.yml.enc',
            'config/private/service_account.json',
            'config/routes.rb'
          ]
        }
        allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:conventions).and_return(conventions)

        payload = described_class.send(:resolve_resource_payload, 'rails://conventions')

        expect(payload[:architecture]).to eq(['mvc'])
        expect(payload[:config_files]).to eq(['config/database.yml', 'config/routes.rb'])
      end

      it 'returns nil for unknown resources' do
        payload = described_class.send(:resolve_resource_payload, 'rails://unknown')
        expect(payload).to be_nil
      end
    end

    describe 'bridge_metadata' do
      it 'includes bridge configuration' do
        metadata = described_class.send(:bridge_metadata)

        expect(metadata[:bridge_version]).to eq(RailsAiBridge::VERSION)
        expect(metadata[:app_name]).to eq('TestApp')
        expect(metadata[:available_resources]).to include('rails://bridge/meta')
        expect(metadata[:available_sections]).to include('app_name', 'models', 'stimulus')
      end
    end

    describe 'read_stimulus_resource' do
      it 'finds controller by case-insensitive name' do
        result = described_class.send(:read_stimulus_resource, 'HELLO')
        expect(result).to eq({ name: 'hello' })
      end

      it 'returns error for unknown controller' do
        result = described_class.send(:read_stimulus_resource, 'unknown')
        expect(result).to eq({ error: "Stimulus controller 'unknown' not found" })
      end

      it 'handles empty controllers array' do
        allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:stimulus).and_return({ controllers: [] })
        result = described_class.send(:read_stimulus_resource, 'hello')
        expect(result).to eq({ error: "Stimulus controller 'hello' not found" })
      end

      it 'handles nil stimulus data' do
        allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:stimulus).and_return(nil)
        result = described_class.send(:read_stimulus_resource, 'hello')
        expect(result).to eq({ error: "Stimulus controller 'hello' not found" })
      end
    end

    describe 'read_model_resource' do
      it 'handles URL-encoded model names' do
        allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:models).and_return({ 'User::Profile' => { name: 'User::Profile' } })
        result = described_class.send(:read_model_resource, 'rails://models/User%3A%3AProfile')
        expect(result).to eq({ name: 'User::Profile' })
      end

      it 'returns error for non-existent model' do
        result = described_class.send(:read_model_resource, 'rails://models/NonExistent')
        expect(result).to eq({ error: "Model 'NonExistent' not found" })
      end

      it 'handles nil models data' do
        allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:models).and_return(nil)
        result = described_class.send(:read_model_resource, 'rails://models/User')
        expect(result).to eq({ error: "Model 'User' not found" })
      end
    end

    describe 'json_resource' do
      it 'formats payload as JSON with proper structure' do
        payload = { test: 'data' }
        result = described_class.send(:json_resource, 'rails://test', payload)

        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first[:uri]).to eq('rails://test')
        expect(result.first[:mime_type]).to eq('application/json')
        expect(result.first[:text]).to include('"test": "data"')
      end

      it 'handles complex nested objects' do
        payload = { nested: { array: [1, 2, 3], hash: { key: 'value' } } }
        result = described_class.send(:json_resource, 'rails://test', payload)

        expect(result.first[:text]).to include('"nested"')
        expect(result.first[:text]).to include('"array"')
        expect(result.first[:text]).to include('1')
        expect(result.first[:text]).to include('2')
        expect(result.first[:text]).to include('3')
      end

      it 'handles nil payload gracefully' do
        payload = nil
        result = described_class.send(:json_resource, 'rails://test', payload)

        expect(result.first[:text]).to eq('null')
      end
    end
  end
end
