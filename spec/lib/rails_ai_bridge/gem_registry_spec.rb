# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::GemRegistry do
  describe 'NOTABLE_GEMS' do
    subject(:registry) { described_class::NOTABLE_GEMS }

    it 'is a frozen non-empty hash' do
      expect(registry).to be_a(Hash).and be_frozen
      expect(registry).not_to be_empty
    end

    it 'every entry has :category and :note keys' do
      registry.each do |name, info|
        expect(info).to have_key(:category), "#{name} is missing :category"
        expect(info).to have_key(:note), "#{name} is missing :note"
        expect(info[:note]).to be_a(String).and be_present
      end
    end

    it 'covers the expected categories' do
      categories = registry.values.pluck(:category).uniq
      expect(categories).to include(:auth, :jobs, :frontend, :api, :database, :testing)
    end

    it 'includes key well-known gems' do
      expect(registry).to include('devise', 'sidekiq', 'turbo-rails', 'pg', 'rspec-rails')
    end
  end

  describe '.categorize' do
    let(:notable) do
      [
        { name: 'devise',   category: 'auth',     note: 'Auth.' },
        { name: 'pundit',   category: 'auth',     note: 'Policies.' },
        { name: 'sidekiq',  category: 'jobs',     note: 'Jobs.' }
      ]
    end

    it 'groups gem names by category' do
      result = described_class.categorize(notable)
      expect(result['auth']).to contain_exactly('devise', 'pundit')
      expect(result['jobs']).to contain_exactly('sidekiq')
    end

    it 'returns an empty hash for empty input' do
      expect(described_class.categorize([])).to eq({})
    end
  end
end
