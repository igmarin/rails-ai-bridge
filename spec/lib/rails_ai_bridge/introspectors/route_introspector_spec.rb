# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::RouteIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

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

    it 'returns api_namespaces as an array' do
      expect(result[:api_namespaces]).to be_an(Array)
    end

    it 'returns mounted_engines as an array' do
      expect(result[:mounted_engines]).to be_an(Array)
    end
  end
end
