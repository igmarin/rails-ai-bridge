# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::MigrationIntrospector do
  let(:app) { Rails.application }
  let(:introspector) { described_class.new(app) }

  let(:migrate_dir) { File.join(app.root.to_s, 'db/migrate') }

  before do
    FileUtils.mkdir_p(migrate_dir)

    File.write(File.join(migrate_dir, '20240101120000_create_users.rb'), <<~RUBY)
      class CreateUsers < ActiveRecord::Migration[7.1]
        def change
          create_table :users do |t|
            t.string :email
            t.timestamps
          end
          add_index :users, :email, unique: true
        end
      end
    RUBY

    File.write(File.join(migrate_dir, '20240215080000_add_name_to_users.rb'), <<~RUBY)
      class AddNameToUsers < ActiveRecord::Migration[7.1]
        def change
          add_column :users, :name, :string
        end
      end
    RUBY

    File.write(File.join(migrate_dir, '20240320090000_create_posts.rb'), <<~RUBY)
      class CreatePosts < ActiveRecord::Migration[7.1]
        def change
          create_table :posts do |t|
            t.references :user, foreign_key: true
            t.string :title
            t.timestamps
          end
        end
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(migrate_dir)
  end

  describe '#call' do
    subject(:result) { introspector.call }

    it 'returns total migration count' do
      expect(result[:total]).to eq(3)
    end

    it 'returns recent migrations in reverse order' do
      recent = result[:recent]
      expect(recent.first[:filename]).to eq('20240320090000_create_posts.rb')
      expect(recent.last[:filename]).to eq('20240101120000_create_users.rb')
    end

    it 'detects migration actions' do
      create_users = result[:recent].find { |m| m[:filename].include?('create_users') }
      expect(create_users[:actions]).to include('create_table', 'add_index')
    end

    it 'detects add_column actions' do
      add_name = result[:recent].find { |m| m[:filename].include?('add_name') }
      expect(add_name[:actions]).to include('add_column')
    end

    it 'returns migration stats' do
      stats = result[:migration_stats]
      expect(stats[:total_create_table]).to eq(2)
      expect(stats[:total_add_column]).to eq(1)
      expect(stats[:by_year]).to include('2024' => 3)
    end

    it 'does not return an error' do
      expect(result[:error]).to be_nil
    end
  end

  describe '#call with no migrate dir' do
    let(:result) { introspector.call }

    before { FileUtils.rm_rf(migrate_dir) }
    # Clean up migration files created by the outer before hook
    after { FileUtils.rm_rf(migrate_dir) }

    it 'returns total of 0' do
      expect(result[:total]).to eq(0)
    end

    it 'returns empty migration_stats' do
      expect(result[:migration_stats]).to eq({})
    end
  end

  describe '#call with schema version' do
    let(:schema_path) { File.join(app.root.to_s, 'db/schema.rb') }
    let(:original_schema) { File.exist?(schema_path) ? File.read(schema_path) : nil }
    let(:result) { introspector.call }

    before do
      original_schema
      File.write(schema_path, "ActiveRecord::Schema[7.1].define(version: 2024_02_15_08_00_00) do\nend\n")
    end

    after do
      if original_schema
        File.write(schema_path, original_schema)
      else
        FileUtils.rm_f(schema_path)
      end
    end

    it 'detects schema version from schema.rb' do
      expect(result[:schema_version]).to eq('20240215080000')
    end

    it 'detects pending migrations after schema version' do
      pending = result[:pending]
      pending_versions = pending.pluck(:version)
      expect(pending_versions).to include('20240320090000')
      expect(pending_versions).not_to include('20240101120000')
    end
  end

  describe '#call with no schema.rb' do
    let(:schema_path) { File.join(app.root.to_s, 'db/schema.rb') }
    let(:original_schema) { File.exist?(schema_path) ? File.read(schema_path) : nil }
    let(:result) { introspector.call }

    before do
      original_schema
      FileUtils.rm_f(schema_path)
    end

    after do
      if original_schema
        File.write(schema_path, original_schema)
      else
        FileUtils.rm_f(schema_path)
      end
    end

    it 'returns nil schema_version' do
      expect(result[:schema_version]).to be_nil
    end

    it 'returns empty pending migrations when no schema version' do
      expect(result[:pending]).to eq([])
    end
  end

  describe '#call with unreadable migration file' do
    let(:bad_migration) { File.join(migrate_dir, '20240101000000_bad.rb') }
    let(:result) { introspector.call }

    before do
      File.write(bad_migration, 'not valid ruby')
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(bad_migration).and_raise(StandardError, 'read error')
    end

    after { allow(File).to receive(:read).and_call_original }

    it 'includes error entry for unreadable migration' do
      bad = result[:recent].find { |m| m[:version] == 'unknown' }
      expect(bad).not_to be_nil
      expect(bad[:name]).to eq('20240101000000_bad.rb')
      expect(bad[:error]).to eq('read error')
    end
  end

  describe '#call with short version migration' do
    let(:short_version_migration) { File.join(migrate_dir, '123_create_short.rb') }
    let(:result) { introspector.call }

    before do
      File.write(short_version_migration, <<~RUBY)
        class CreateShort < ActiveRecord::Migration[7.1]
          def change
            create_table :shorts
          end
        end
      RUBY
    end

    after { FileUtils.rm_f(short_version_migration) }

    it 'groups short version migrations under unknown year' do
      stats = result[:migration_stats]
      expect(stats[:by_year]).to have_key('unknown')
    end
  end

  describe '#call when app.root raises' do
    let(:bad_app) { double('Rails::Application') }
    let(:result) { described_class.new(bad_app).call }

    before { allow(bad_app).to receive(:root).and_raise(StandardError, 'root boom') }

    it 'returns error hash' do
      expect(result[:error]).to eq('root boom')
    end
  end
end
