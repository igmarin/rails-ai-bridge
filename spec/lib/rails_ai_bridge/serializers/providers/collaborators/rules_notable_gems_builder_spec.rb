# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::Collaborators::RulesNotableGemsBuilder do
  describe '#call' do
    it 'sorts notable gems by category and name' do
      gems = {
        notable_gems: [
          { name: 'rubocop', version: '1.0', category: 'tooling', note: 'Code style linter' },
          { name: 'devise', version: '4.9.0', category: 'auth', note: 'Authentication solution' }
        ]
      }

      result = described_class.new(gems).call

      expect(result).to eq([
                             '## Notable Gems',
                             '- `devise` (`4.9.0`): Authentication solution',
                             '- `rubocop` (`1.0`): Code style linter'
                           ])
    end

    it 'falls back to notable gems under :notable' do
      gems = { notable: [{ name: 'sidekiq', version: '7.0', category: 'jobs', note: 'Background jobs' }] }

      result = described_class.new(gems).call

      expect(result).to include('- `sidekiq` (`7.0`): Background jobs')
    end

    it 'falls back to notable gems under :detected' do
      gems = { detected: [{ name: 'pg', version: '1.5', category: 'database', note: 'PostgreSQL adapter' }] }

      result = described_class.new(gems).call

      expect(result).to include('- `pg` (`1.5`): PostgreSQL adapter')
    end

    it 'filters malformed gem entries' do
      gems = { notable_gems: [{ name: 'devise', version: '4.9.0', category: 'auth', note: 'Authentication solution' }, 'oops'] }

      result = described_class.new(gems).call

      expect(result).to eq([
                             '## Notable Gems',
                             '- `devise` (`4.9.0`): Authentication solution'
                           ])
    end

    it 'returns an empty array for malformed gem payloads' do
      expect(described_class.new(notable_gems: 'oops').call).to eq([])
    end
  end
end
