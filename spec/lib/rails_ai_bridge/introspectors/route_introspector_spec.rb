# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::RouteIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  before do
    Rails.application.reload_routes!
  end

  describe '#call' do
    subject(:result) { introspector.call }

    it 'counts total routes' do
      expect(result[:total_routes]).to be > 0
    end

    it 'groups routes by controller' do
      expect(result[:by_controller]).to have_key('users')
      expect(result[:by_controller]).to have_key('posts')
    end

    it 'extracts HTTP verbs and paths' do
      user_routes = result[:by_controller]['users']
      expect(user_routes).to include(a_hash_including(verb: 'GET', path: '/users'))
    end

    it 'omits routes for an excluded model and table' do
      unfiltered = described_class.new(Rails.application).call
      original_models = RailsAiBridge.configuration.excluded_models.dup
      original_tables = RailsAiBridge.configuration.excluded_tables.dup
      RailsAiBridge.configuration.excluded_models += %w[User]
      RailsAiBridge.configuration.excluded_tables += %w[users]

      filtered = described_class.new(Rails.application).call

      expect(unfiltered[:by_controller]).to have_key('users')
      expect(filtered[:by_controller]).not_to have_key('users')
      expect(filtered[:by_controller]).to have_key('posts')
      expect(filtered[:total_routes]).to eq(unfiltered[:total_routes] - unfiltered[:by_controller]['users'].size)
    ensure
      RailsAiBridge.configuration.excluded_models = original_models
      RailsAiBridge.configuration.excluded_tables = original_tables
    end

    it 'returns api_namespaces as an array' do
      expect(result[:api_namespaces]).to be_an(Array)
    end

    it 'returns mounted_engines as an array' do
      expect(result[:mounted_engines]).to be_an(Array)
    end
  end
end
