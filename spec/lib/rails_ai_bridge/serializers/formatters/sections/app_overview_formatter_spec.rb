# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/serializers/formatters/sections/app_overview_formatter'

RSpec.describe RailsAiBridge::Serializers::Formatters::Sections::AppOverviewFormatter do
  describe '#call' do
    it 'returns nil when the app_overview key is absent from context' do
      expect(described_class.new({}).call).to be_nil
    end

    it 'returns nil when app_overview has an :error key' do
      expect(described_class.new({ app_overview: { error: 'failed' } }).call).to be_nil
    end

    it 'returns nil when neither app_name nor rails_version is present' do
      expect(described_class.new({ app_overview: {} }).call).to be_nil
    end

    it 'renders the Application Overview heading when app_name is present' do
      result = described_class.new({ app_overview: { app_name: 'MyApp' } }).call
      expect(result).to include('# Application Overview')
      expect(result).to include('**Name:** `MyApp`')
    end

    it 'renders rails_version when present' do
      result = described_class.new({ app_overview: { rails_version: '7.1.3' } }).call
      expect(result).to include('**Rails:** `7.1.3`')
    end

    it 'renders ruby_version when present' do
      result = described_class.new({ app_overview: { app_name: 'App', ruby_version: '3.3.0' } }).call
      expect(result).to include('**Ruby:** `3.3.0`')
    end

    it 'renders environment when present' do
      result = described_class.new({ app_overview: { app_name: 'App', environment: 'production' } }).call
      expect(result).to include('**Environment:** `production`')
    end

    it 'renders database_adapter when present' do
      result = described_class.new({ app_overview: { app_name: 'App', database_adapter: 'postgresql' } }).call
      expect(result).to include('**Database:** `postgresql`')
    end

    it 'omits optional fields when they are absent' do
      result = described_class.new({ app_overview: { app_name: 'App' } }).call
      expect(result).not_to include('Ruby')
      expect(result).not_to include('Environment')
      expect(result).not_to include('Database')
    end

    it 'renders all fields in the correct order when fully populated' do
      data = {
        app_name: 'FullApp',
        rails_version: '7.1.3',
        ruby_version: '3.3.0',
        environment: 'development',
        database_adapter: 'sqlite3'
      }
      result = described_class.new({ app_overview: data }).call
      expect(result).to include('**Name:** `FullApp`')
      expect(result).to include('**Rails:** `7.1.3`')
      expect(result).to include('**Ruby:** `3.3.0`')
      expect(result).to include('**Environment:** `development`')
      expect(result).to include('**Database:** `sqlite3`')
      # Verify order
      name_pos = result.index('**Name:**')
      rails_pos = result.index('**Rails:**')
      ruby_pos = result.index('**Ruby:**')
      expect(name_pos).to be < rails_pos
      expect(rails_pos).to be < ruby_pos
    end
  end
end
