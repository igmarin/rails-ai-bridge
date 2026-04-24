# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::GetConfig do
  let(:config_data) do
    {
      cache_store: ':memory_store',
      session_store: ':cookie_store',
      timezone: 'UTC',
      middleware_stack: [
        'ActionDispatch::HostAuthorization',
        'Rack::Sendfile'
      ],
      initializers: %w[
        active_storage
        action_cable
      ],
      current_attributes: [
        'Current.user',
        'Current.request_id'
      ]
    }
  end
  let(:response) { described_class.call }
  let(:content) { response.content.first[:text] }

  before do
    allow(described_class).to receive(:cached_section).with(:config).and_return(config_data)
  end

  describe '.call' do
    context 'when all config data is present' do
      it 'returns a formatted markdown string with all sections' do
        expect(content).to include('# Application Configuration')
        expect(content).to include('- **Cache store:** :memory_store')
        expect(content).to include('- **Session store:** :cookie_store')
        expect(content).to include('- **Timezone:** UTC')
        expect(content).to include('## Middleware Stack')
        expect(content).to include('- ActionDispatch::HostAuthorization')
        expect(content).to include('## Initializers')
        expect(content).to include('- `active_storage`')
        expect(content).to include('## CurrentAttributes')
        expect(content).to include('- `Current.user`')
      end
    end

    context 'when some config data is missing' do
      let(:config_data) do
        {
          cache_store: ':memory_store',
          initializers: ['action_cable']
        }
      end

      it 'returns a formatted string omitting the missing sections' do
        expect(content).to include('- **Cache store:** :memory_store')
        expect(content).to include('## Initializers')
        expect(content).to include('- `action_cable`')
        expect(content).not_to include('- **Session store:**')
        expect(content).not_to include('## Middleware Stack')
        expect(content).not_to include('## CurrentAttributes')
      end
    end

    context 'when config introspection is not available' do
      let(:config_data) { nil }

      it 'returns an informative message' do
        expect(content).to include('Config introspection not available.')
      end
    end

    context 'when config introspection has an error' do
      let(:config_data) { { error: 'Something went wrong' } }

      it 'returns the error message' do
        expect(content).to include('Config introspection failed: Something went wrong')
      end
    end
  end
end
