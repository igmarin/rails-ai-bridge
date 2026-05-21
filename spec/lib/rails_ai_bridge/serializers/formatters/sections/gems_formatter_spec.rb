# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/serializers/formatters/sections/gems_formatter'

RSpec.describe RailsAiBridge::Serializers::Formatters::Sections::GemsFormatter do
  describe '#call' do
    it 'returns nil when the gems key is absent' do
      expect(described_class.new({}).call).to be_nil
    end

    it 'returns nil when gems has an :error key' do
      expect(described_class.new({ gems: { error: 'something went wrong' } }).call).to be_nil
    end

    it 'returns nil when total_gems is not present' do
      expect(described_class.new({ gems: { notable_gems: [] } }).call).to be_nil
    end

    it 'renders the Gems heading with total count' do
      result = described_class.new({ gems: { total_gems: 42 } }).call
      expect(result).to include('## Gems')
      expect(result).to include('Total gems: `42`')
    end

    it 'omits Notable Gems section when notable_gems is absent' do
      result = described_class.new({ gems: { total_gems: 10 } }).call
      expect(result).not_to include('### Notable Gems')
    end

    it 'omits Notable Gems section when notable_gems is an empty array' do
      result = described_class.new({ gems: { total_gems: 10, notable_gems: [] } }).call
      expect(result).not_to include('### Notable Gems')
    end

    it 'renders Notable Gems when present' do
      gems = [
        { name: 'devise', version: '4.9.2', category: 'auth', note: 'Authentication' },
        { name: 'sidekiq', version: '7.0.0', category: 'background', note: 'Background jobs' }
      ]
      result = described_class.new({ gems: { total_gems: 50, notable_gems: gems } }).call
      expect(result).to include('### Notable Gems')
      expect(result).to include('`devise` (`4.9.2`): Authentication')
      expect(result).to include('`sidekiq` (`7.0.0`): Background jobs')
    end

    it 'sorts notable gems by category then name' do
      gems = [
        { name: 'sidekiq', version: '7.0.0', category: 'background', note: 'Background jobs' },
        { name: 'devise', version: '4.9.2', category: 'auth', note: 'Authentication' },
        { name: 'cancancan', version: '3.5.0', category: 'auth', note: 'Authorization' }
      ]
      result = described_class.new({ gems: { total_gems: 50, notable_gems: gems } }).call
      # 'auth' < 'background' so auth gems appear first
      # within 'auth': 'cancancan' < 'devise' alphabetically
      cancan_pos = result.index('`cancancan`')
      devise_pos = result.index('`devise`')
      sidekiq_pos = result.index('`sidekiq`')
      expect(cancan_pos).to be < devise_pos   # cancancan before devise (alphabetical within auth)
      expect(devise_pos).to be < sidekiq_pos  # auth before background
    end
  end
end
