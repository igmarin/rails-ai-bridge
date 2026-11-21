# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::Collaborators::RulesArchitectureBuilder do
  subject(:builder) { described_class.new(conventions) }

  describe '#call' do
    it 'returns heading plus humanized entries' do
      result = described_class.new(
        { architecture: ['service_objects', 'fat-free models'] }
      ).call

      expect(result).to eq([
                             '## Architecture & Conventions',
                             '- Service objects',
                             '- Fat-free models'
                           ])
    end

    it 'returns empty when conventions is not a hash' do
      expect(described_class.new('invalid').call).to eq([])
    end

    it 'returns empty when architecture key is missing' do
      expect(described_class.new({ models: {} }).call).to eq([])
    end

    it 'returns empty when architecture list is empty' do
      expect(described_class.new({ architecture: [] }).call).to eq([])
    end
  end
end
