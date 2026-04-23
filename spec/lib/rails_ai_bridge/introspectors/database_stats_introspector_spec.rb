# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::DatabaseStatsIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    it 'returns skipped for non-PostgreSQL adapter' do
      result = introspector.call
      # Test suite uses SQLite — should skip
      expect(result[:skipped]).to be(true)
      expect(result[:reason]).to include('PostgreSQL')
    end
  end
end
