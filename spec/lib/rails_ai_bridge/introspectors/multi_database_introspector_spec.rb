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

  describe 'private methods' do
    describe '#anonymize_db_name' do
      it 'returns name unchanged for regular names' do
        expect(introspector.send(:anonymize_db_name, 'my_app_development')).to eq('my_app_development')
      end

      it 'extracts path from postgres URL' do
        expect(introspector.send(:anonymize_db_name, 'postgres://localhost/mydb')).to eq('mydb')
      end

      it 'extracts path from mysql URL' do
        expect(introspector.send(:anonymize_db_name, 'mysql://localhost/mydb')).to eq('mydb')
      end

      it 'returns external on URI parse error' do
        allow(URI).to receive(:parse).and_raise(URI::InvalidURIError)
        expect(introspector.send(:anonymize_db_name, 'postgres://bad')).to eq('external')
      end

      it 'returns nil for nil input' do
        expect(introspector.send(:anonymize_db_name, nil)).to be_nil
      end
    end

    describe '#detect_sharding' do
      it 'returns nil when database.yml does not exist' do
        expect(introspector.send(:detect_sharding)).to be_nil
      end

      it 'returns nil on file read error' do
        config_dir = File.join(root, 'config')
        FileUtils.mkdir_p(config_dir)
        db_path = File.join(config_dir, 'database.yml')
        File.write(db_path, 'development:')
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(db_path).and_raise(StandardError, 'read error')
        expect(introspector.send(:detect_sharding)).to be_nil
      ensure
        allow(File).to receive(:read).and_call_original
      end
    end

    describe '#detect_model_connections' do
      it 'returns empty array when models dir does not exist' do
        expect(introspector.send(:detect_model_connections)).to eq([])
      end

      it 'handles file read errors gracefully' do
        models_dir = File.join(root, 'app/models')
        FileUtils.mkdir_p(models_dir)
        bad_file = File.join(models_dir, 'bad.rb')
        File.write(bad_file, 'class Bad; end')
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(bad_file).and_raise(StandardError, 'read error')

        expect(introspector.send(:detect_model_connections)).to eq([])
      ensure
        allow(File).to receive(:read).and_call_original
      end
    end

    describe '#discover_replicas error handling' do
      it 'returns empty array on error' do
        allow(ActiveRecord::Base).to receive(:configurations).and_raise(StandardError)
        expect(introspector.send(:discover_replicas)).to eq([])
      end
    end

    describe '#discover_databases error handling' do
      it 'falls back to parse_database_yml on error' do
        allow(ActiveRecord::Base).to receive(:configurations).and_raise(StandardError)
        config_dir = File.join(root, 'config')
        FileUtils.mkdir_p(config_dir)
        File.write(File.join(config_dir, 'database.yml'), "development:\n  primary:\n")
        allow(Rails).to receive(:env).and_return('development')

        result = introspector.send(:discover_databases)
        expect(result).to be_an(Array)
      end
    end
  end
end
