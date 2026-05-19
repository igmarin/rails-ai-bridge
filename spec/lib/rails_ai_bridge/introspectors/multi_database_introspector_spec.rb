# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::MultiDatabaseIntrospector do
  let(:app) { Rails.application }
  let(:introspector) { described_class.new(app) }
  let(:root) { Dir.mktmpdir }

  before do
    allow(app).to receive(:root).and_return(Pathname.new(root))
  end

  after do
    FileUtils.remove_entry(root)
  end

  describe '#call' do
    it 'returns fallback data when ActiveRecord is not defined' do
      hide_const('ActiveRecord::Base')
      result = introspector.call
      expect(result[:databases]).to be_an(Array)
      expect(result[:replicas]).to eq([])
    end

    it 'detects sharding from database.yml' do
      config_dir = File.join(root, 'config')
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, 'database.yml'), "development:\n  primary:\n  primary_shard_one:")

      result = introspector.call
      expect(result[:sharding]).to include(detected: true)
    end

    it 'detects model connections correctly' do
      models_dir = File.join(root, 'app/models')
      FileUtils.mkdir_p(models_dir)

      File.write(File.join(models_dir, 'reader.rb'), <<~RUBY)
        class Reader < ApplicationRecord
          connects_to database: { reading: :replica }
        end
      RUBY

      File.write(File.join(models_dir, 'writer.rb'), <<~RUBY)
        class Writer < ApplicationRecord
          connected_to(role: :reading)
        end
      RUBY

      result = introspector.call
      expect(result[:model_connections].size).to eq(2)
      expect(result[:model_connections].first[:model]).to eq('Reader')
      expect(result[:model_connections].last[:model]).to eq('Writer')
      expect(result[:model_connections].last[:uses_connected_to]).to be(true)
    end

    it 'handles errors gracefully' do
      allow(introspector).to receive(:discover_databases).and_raise(StandardError, 'Oops')
      expect(introspector.call).to eq({ error: 'Oops' })
    end
  end

  describe '#parse_database_yml' do
    it 'parses database.yml for fallback' do
      config_dir = File.join(root, 'config')
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, 'database.yml'), <<~YML)
        development:
          primary:
            adapter: postgresql
          animals:
            adapter: postgresql
        test:
          primary:
      YML

      hide_const('ActiveRecord::Base')
      allow(Rails).to receive(:env).and_return('development')

      result = introspector.call
      expect(result[:databases]).to include({ name: 'primary' }, { name: 'animals' })
    end
  end
end
