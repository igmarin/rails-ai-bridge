# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::GetTestInfo do
  describe '.call' do
    let(:test_data) do
      {
        framework: 'RSpec',
        factories: { location: 'spec/factories', count: 10 },
        fixtures: { location: 'spec/fixtures', count: 5 },
        system_tests: { location: 'spec/system' },
        ci_config: ['workflows/ci.yml'],
        coverage: 'SimpleCov',
        test_helpers: ['spec/support/helpers.rb']
      }
    end

    before do
      allow(described_class).to receive(:cached_section).with(:tests).and_return(test_data)
    end

    context 'when all test data is present' do
      it 'returns a formatted markdown string with all sections' do
        response = described_class.call
        content = response.content.first[:text]

        expect(response).to be_a(MCP::Tool::Response)
        expect(content).to include('# Test Infrastructure')
        expect(content).to include('- **Framework:** RSpec')
        expect(content).to include('- **Factories:** spec/factories (10 files)')
        expect(content).to include('- **Fixtures:** spec/fixtures (5 files)')
        expect(content).to include('- **System tests:** spec/system')
        expect(content).to include('- **CI:** workflows/ci.yml')
        expect(content).to include('- **Coverage:** SimpleCov')
        expect(content).to include('## Test Helpers')
        expect(content).to include('- `spec/support/helpers.rb`')
      end
    end

    context 'when some test data is missing' do
      let(:test_data) do
        {
          framework: 'Minitest',
          ci_config: ['workflows/ci.yml', 'workflows/release.yml']
        }
      end

      it 'returns a formatted string omitting the missing sections' do
        response = described_class.call
        content = response.content.first[:text]

        expect(content).to include('- **Framework:** Minitest')
        expect(content).to include('- **CI:** workflows/ci.yml, workflows/release.yml')
        expect(content).not_to include('- **Factories**')
        expect(content).not_to include('- **Fixtures**')
        expect(content).not_to include('## Test Helpers')
      end
    end

    context 'when test introspection is not available' do
      let(:test_data) { nil }

      it 'returns a helpful message' do
        response = described_class.call
        expect(response.content.first[:text]).to include('Test introspection not available')
      end
    end

    context 'when test introspection has an error' do
      let(:test_data) { { error: 'Something went wrong' } }

      it 'returns the error message' do
        response = described_class.call
        expect(response.content.first[:text]).to include('Test introspection failed: Something went wrong')
      end
    end
  end
end
