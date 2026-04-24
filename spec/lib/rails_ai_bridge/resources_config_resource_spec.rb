# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Resources do
  describe 'rails://config resource JSON' do
    around do |example|
      saved_introspectors = RailsAiBridge.configuration.introspectors.dup
      saved_expose = RailsAiBridge.configuration.expose_credentials_key_names
      RailsAiBridge.configuration.introspectors |= [:config]
      example.run
    ensure
      RailsAiBridge.configuration.introspectors = saved_introspectors
      RailsAiBridge.configuration.expose_credentials_key_names = saved_expose
    end

    it 'does not include credentials_keys when expose_credentials_key_names is false' do
      RailsAiBridge.configuration.expose_credentials_key_names = false
      rows = described_class.send(:handle_read, { uri: 'rails://config' })
      json = JSON.parse(rows.first[:text])
      expect(json).not_to have_key('credentials_keys')
    end
  end

  describe 'additional resources' do
    around do |example|
      saved_resources = RailsAiBridge.configuration.additional_resources.dup
      example.run
    ensure
      RailsAiBridge.configuration.additional_resources = saved_resources
    end

    it 'reads configured custom resources through the shared context provider' do
      RailsAiBridge.configuration.additional_resources['rails://custom'] = {
        name: 'Custom',
        description: 'Custom resource',
        mime_type: 'application/json',
        key: :custom
      }
      allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:custom).and_return({ 'value' => 7 })

      rows = described_class.send(:handle_read, { uri: 'rails://custom' })
      json = JSON.parse(rows.first[:text])

      expect(json).to eq({ 'value' => 7 })
      expect(RailsAiBridge::ContextProvider).to have_received(:fetch_section).with(:custom)
    end
  end

  describe 'bridge resources' do
    it 'exposes bridge metadata' do
      allow(RailsAiBridge::ContextProvider).to receive(:fetch)
        .and_return({
                      app_name: 'Dummy',
                      generated_at: '2026-03-21T00:00:00Z',
                      schema: {}
                    })

      rows = described_class.send(:handle_read, { uri: 'rails://bridge/meta' })
      json = JSON.parse(rows.first[:text])

      expect(json['bridge_version']).to eq(RailsAiBridge::VERSION)
      expect(json['available_tools']).to include('rails_get_schema')
      expect(json['enabled_introspectors']).to include('schema')
    end

    it 'reads a specific stimulus controller resource' do
      allow(RailsAiBridge::ContextProvider).to receive(:fetch_section)
        .with(:stimulus)
        .and_return({
                      controllers: [
                        {
                          name: 'clipboard', file: 'clipboard_controller.js', targets: ['source']
                        }
                      ]
                    })

      rows = described_class.send(:handle_read, { uri: 'rails://stimulus/clipboard' })
      json = JSON.parse(rows.first[:text])

      expect(json['name']).to eq('clipboard')
      expect(json['file']).to eq('clipboard_controller.js')
    end

    it 'decodes namespaced model resource identifiers' do
      allow(RailsAiBridge::ContextProvider).to receive(:fetch_section)
        .with(:models)
        .and_return({
                      'Admin::User' => { table_name: 'admin_users' }
                    })

      rows = described_class.send(:handle_read, { uri: 'rails://models/Admin%3A%3AUser' })
      json = JSON.parse(rows.first[:text])

      expect(json['table_name']).to eq('admin_users')
    end

    it 'reads a specific view resource from app/views' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'app/views/users'))
        File.write(File.join(dir, 'app/views/users/index.html.erb'), "<%= render 'form' %>")

        allow(Rails).to receive(:root).and_return(Pathname.new(dir))

        rows = described_class.send(:handle_read, { uri: 'rails://views/users/index.html.erb' })
        json = JSON.parse(rows.first[:text])

        expect(json['path']).to eq('users/index.html.erb')
        expect(json['renders']).to include('form')
      end
    end

    it 'raises for unknown resources' do
      expect do
        described_class.send(:handle_read, { uri: 'rails://unknown/resource' })
      end.to raise_error(RuntimeError, 'Unknown resource: rails://unknown/resource')
    end
  end
end
