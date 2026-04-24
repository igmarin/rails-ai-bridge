# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::Schema::StaticSchemaParser do
  let(:config) { RailsAiBridge.configuration }

  def parse(content)
    described_class.new(content: content, config: config).call
  end

  # ---------------------------------------------------------------------------
  # Shape of the result
  # ---------------------------------------------------------------------------
  describe 'result shape' do
    let(:content) do
      <<~RUBY
        ActiveRecord::Schema[7.2].define(version: 2024_01_01_000000) do
          create_table "users", force: :cascade do |t|
            t.string "email", null: false
            t.integer "age"
          end
        end
      RUBY
    end

    it 'returns a Hash' do
      expect(parse(content)).to be_a(Hash)
    end

    it 'sets adapter to static_parse' do
      expect(parse(content)[:adapter]).to eq('static_parse')
    end

    it 'includes a note about the parse source' do
      expect(parse(content)[:note]).to include('schema.rb')
    end

    it 'total_tables equals the number of tables parsed' do
      result = parse(content)
      expect(result[:total_tables]).to eq(result[:tables].size)
    end
  end

  # ---------------------------------------------------------------------------
  # Table parsing
  # ---------------------------------------------------------------------------
  describe 'table parsing' do
    let(:content) do
      <<~RUBY
        ActiveRecord::Schema[7.2].define(version: 2024_01_01_000000) do
          create_table "users", force: :cascade do |t|
            t.string "email"
          end
          create_table "posts", force: :cascade do |t|
            t.string "title"
          end
        end
      RUBY
    end

    it 'captures each create_table as a table key' do
      expect(parse(content)[:tables].keys).to contain_exactly('users', 'posts')
    end

    it 'initialises each table with empty indexes and foreign_keys arrays' do
      result = parse(content)
      expect(result[:tables]['users'][:indexes]).to eq([])
      expect(result[:tables]['users'][:foreign_keys]).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Column parsing
  # ---------------------------------------------------------------------------
  describe 'column parsing' do
    let(:content) do
      <<~RUBY
        ActiveRecord::Schema[7.2].define(version: 2024_01_01_000000) do
          create_table "users", force: :cascade do |t|
            t.string  "email"
            t.integer "age"
            t.boolean "active"
          end
        end
      RUBY
    end

    it 'captures column names' do
      columns = parse(content)[:tables]['users'][:columns]
      expect(columns.pluck(:name)).to contain_exactly('email', 'age', 'active')
    end

    it 'captures column types' do
      columns = parse(content)[:tables]['users'][:columns]
      email_col = columns.find { |c| c[:name] == 'email' }
      expect(email_col[:type]).to eq('string')
    end

    it 'does not capture columns outside a table block' do
      content = "t.string \"orphan\"\n"
      expect(parse(content)[:tables]).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Index parsing
  # ---------------------------------------------------------------------------
  describe 'index parsing' do
    let(:content) do
      <<~RUBY
        ActiveRecord::Schema[7.2].define(version: 2024_01_01_000000) do
          create_table "users", force: :cascade do |t|
            t.string "email"
          end
          add_index "users", "email", unique: true
          add_index "users", ["email"]
        end
      RUBY
    end

    it 'adds an index entry to the matching table' do
      indexes = parse(content)[:tables]['users'][:indexes]
      expect(indexes.size).to eq(2)
    end

    it 'records the column name on each index entry' do
      indexes = parse(content)[:tables]['users'][:indexes]
      expect(indexes.pluck(:columns)).to all(eq('email'))
    end

    it 'ignores add_index for a table not in the schema' do
      content = "add_index \"unknown\", \"col\"\n"
      expect(parse(content)[:tables]).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Internal table filtering
  # ---------------------------------------------------------------------------
  describe 'internal table filtering' do
    let(:content) do
      <<~RUBY
        ActiveRecord::Schema[7.2].define(version: 2024_01_01_000000) do
          create_table "ar_internal_metadata", force: :cascade do |t|
            t.string "key"
          end
          create_table "schema_migrations", force: :cascade do |t|
            t.string "version"
          end
          create_table "users", force: :cascade do |t|
            t.string "email"
          end
        end
      RUBY
    end

    it 'excludes ar_internal_metadata' do
      expect(parse(content)[:tables]).not_to have_key('ar_internal_metadata')
    end

    it 'excludes schema_migrations' do
      expect(parse(content)[:tables]).not_to have_key('schema_migrations')
    end

    it 'keeps application tables' do
      expect(parse(content)[:tables]).to have_key('users')
    end
  end

  # ---------------------------------------------------------------------------
  # Config-driven exclusions
  # ---------------------------------------------------------------------------
  describe 'config-driven exclusions' do
    let(:content) do
      <<~RUBY
        ActiveRecord::Schema[7.2].define(version: 2024_01_01_000000) do
          create_table "users", force: :cascade do |t|
            t.string "email"
          end
          create_table "posts", force: :cascade do |t|
            t.string "title"
          end
          create_table "audit_logs", force: :cascade do |t|
            t.string "action"
          end
        end
      RUBY
    end

    after { config.excluded_tables.clear }

    it 'excludes a table listed in config.excluded_tables' do
      config.excluded_tables << 'users'
      expect(parse(content)[:tables]).not_to have_key('users')
    end

    it 'keeps tables not in the exclusion list' do
      config.excluded_tables << 'users'
      expect(parse(content)[:tables]).to have_key('posts')
    end

    it 'supports glob patterns in excluded_tables' do
      config.excluded_tables << 'audit_*'
      expect(parse(content)[:tables]).not_to have_key('audit_logs')
    end
  end
end
