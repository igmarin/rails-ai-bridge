# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::Collaborators::RulesKeyConsiderationsBuilder do
  subject(:builder) { described_class.new(context) }

  describe '#call' do
    it 'renders heading with both rows when present' do
      result = described_class.new(
        tests: { framework: 'rspec' },
        config: { cache_store: 'memory_store' }
      ).call

      expect(result).to eq([
                             '## Key Development Considerations',
                             '- **Test Framework:** `rspec`',
                             '- **Cache Store:** `memory_store`'
                           ])
    end

    it 'omits absent rows individually' do
      result = described_class.new(tests: { framework: 'rspec' }, config: {}).call

      expect(result).to eq([
                             '## Key Development Considerations',
                             '- **Test Framework:** `rspec`'
                           ])
    end

    it 'returns empty when neither tests nor config exist' do
      expect(described_class.new({}).call).to eq([])
    end

    it 'returns empty when tests and config are not hashes' do
      expect(described_class.new(tests: 'x', config: 'y').call).to eq([])
    end

    it 'treats a non-hash payload section as blank' do
      result = described_class.new(tests: { framework: 'minitest' }, config: 'invalid').call

      expect(result).to eq([
                             '## Key Development Considerations',
                             '- **Test Framework:** `minitest`'
                           ])
    end
  end
end
