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

    it 'includes the Rails path helper and required params for a named route' do
      post_show = result[:by_controller]['posts'].find { |route| route[:action] == 'show' }

      expect(post_show).to include(
        helper: 'post_path',
        required_params: ['id']
      )
    end

    it 'does not invent a helper for an unnamed route' do
      ping = result[:by_controller]['users'].find { |route| route[:path] == '/legacy-ping' }

      expect(ping).to include(verb: 'GET', path: '/legacy-ping', action: 'index')
      expect(ping).not_to have_key(:helper)
    end

    it 'uses the declared route name rather than inventing a helper from the path' do
      profile = result[:by_controller]['users'].find { |route| route[:path] == '/me' }

      expect(profile[:helper]).to eq('profile_path')
      expect(profile[:helper]).not_to eq('me_path')
    end

    it 'returns api_namespaces as an array' do
      expect(result[:api_namespaces]).to be_an(Array)
    end

    it 'returns mounted_engines as an array' do
      expect(result[:mounted_engines]).to be_an(Array)
    end

    it 'omits user routes when only User is excluded' do
      unfiltered = result[:total_routes]
      original_models = RailsAiBridge.configuration.excluded_models.dup
      RailsAiBridge.configuration.excluded_models += %w[User]

      filtered = described_class.new(Rails.application).call

      expect(filtered[:by_controller]).not_to have_key('users')
      expect(filtered[:by_controller]).to have_key('posts')
      expect(filtered[:total_routes]).to be < unfiltered
    ensure
      RailsAiBridge.configuration.excluded_models = original_models
    end

    it 'omits user routes when only the users table is excluded' do
      original_tables = RailsAiBridge.configuration.excluded_tables.dup
      RailsAiBridge.configuration.excluded_tables += %w[users]

      filtered = described_class.new(Rails.application).call

      expect(filtered[:by_controller]).not_to have_key('users')
      expect(filtered[:by_controller]).to have_key('posts')
    ensure
      RailsAiBridge.configuration.excluded_tables = original_tables
    end
  end
end
