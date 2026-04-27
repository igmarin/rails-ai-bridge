# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::Collaborators::RulesModelSectionBuilder do
  subject(:builder) { described_class.new(models: models, config: config) }

  let(:models) do
    {
      'User' => { associations: [{ type: 'has_many', name: 'posts' }] },
      'Post' => { associations: [] },
      'Comment' => { associations: [{ type: 'belongs_to', name: 'post' }] },
      'Profile' => { associations: nil }
    }
  end
  let(:config) { RailsAiBridge::Configuration.new }

  describe '#call' do
    it 'returns a compact models section' do
      result = builder.call

      expect(result).to include('## Models (4 total)')
      expect(result).to include('- Comment (1 associations)')
      expect(result).to include('')
    end

    it 'returns an empty array when models is not a hash' do
      result = described_class.new(models: 'invalid', config: config).call

      expect(result).to eq([])
    end

    it 'returns an empty array when models has error' do
      result = described_class.new(models: { error: 'Failed to load models' }, config: config).call

      expect(result).to eq([])
    end

    it 'returns an empty array when models is empty' do
      result = described_class.new(models: {}, config: config).call

      expect(result).to eq([])
    end

    it 'handles negative limit gracefully' do
      allow(config).to receive(:copilot_compact_model_list_limit).and_return(-1)

      result = builder.call

      expect(result).to include('## Models (4 total)')
      expect(result).to include('- _Use `rails_get_model_details(detail:"summary")` for names._')
    end
  end
end
