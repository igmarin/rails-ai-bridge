# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::GetConventions do
  let(:conventions_data) do
    {
      architecture: %w[api_only hotwire],
      patterns: %w[sti polymorphic],
      directory_structure: {
        'app/controllers' => 10,
        'app/models' => 15
      },
      config_files: ['config/database.yml', 'config/routes.rb']
    }
  end
  let(:response) { described_class.call }
  let(:content) { response.content.first[:text] }

  before do
    allow(described_class).to receive(:cached_section).with(:conventions).and_return(conventions_data)
  end

  describe '.call' do
    context 'when all convention data is present' do
      it 'returns a formatted markdown string with all sections' do
        expect(content).to include('# App Conventions & Architecture')
        expect(content).to include('## Architecture')
        expect(content).to include('- API-only mode (no views/assets)')
        expect(content).to include('- Hotwire (Turbo + Stimulus)')
        expect(content).to include('## Detected patterns')
        expect(content).to include('- Single Table Inheritance (STI)')
        expect(content).to include('- Polymorphic associations')
        expect(content).to include('## Directory structure')
        expect(content).to include('- `app/controllers/` → 10 files')
        expect(content).to include('- `app/models/` → 15 files')
        expect(content).to include('## Config files present')
        expect(content).to include('- `config/database.yml`')
        expect(content).to include('- `config/routes.rb`')
      end

      context 'with secret-bearing config file paths' do
        let(:conventions_data) do
          {
            architecture: ['api_only'],
            config_files: [
              'config/database.yml',
              '.env.local',
              'config/credentials.yml.enc',
              'config/master.key',
              'config/private.key'
            ]
          }
        end

        it 'omits the secret-bearing paths from MCP output' do
          expect(content).to include('- `config/database.yml`')
          expect(content).not_to include('.env')
          expect(content).not_to include('credentials.yml.enc')
          expect(content).not_to include('master.key')
          expect(content).not_to include('private.key')
        end
      end
    end

    context 'when some convention data is missing' do
      let(:conventions_data) do
        {
          architecture: ['api_only'],
          config_files: ['config/database.yml']
        }
      end

      it 'returns a formatted string omitting the missing sections' do
        expect(content).to include('## Architecture')
        expect(content).to include('- API-only mode (no views/assets)')
        expect(content).to include('## Config files present')
        expect(content).to include('- `config/database.yml`')
        expect(content).not_to include('## Detected patterns')
        expect(content).not_to include('## Directory structure')
      end
    end

    context 'when convention introspection is not available' do
      let(:conventions_data) { nil }

      it 'returns an informative message' do
        expect(content).to include('Convention detection not available.')
      end
    end

    context 'when convention introspection has an error' do
      let(:conventions_data) { { error: 'Something went wrong' } }

      it 'returns the error message' do
        expect(content).to include('Convention detection failed: Something went wrong')
      end
    end
  end
end
