# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::SeedsIntrospector do
  let(:app) { Rails.application }
  let(:introspector) { described_class.new(app) }

  let(:db_dir) { File.join(app.root.to_s, 'db') }

  before do
    FileUtils.mkdir_p(db_dir)

    File.write(File.join(db_dir, 'seeds.rb'), <<~RUBY)
      # Default seeds
      if Rails.env.development?
        User.find_or_create_by!(email: "admin@example.com") do |u|
          u.name = "Admin"
        end

        10.times do
          Post.create!(
            title: Faker::Lorem.sentence,
            user: User.first
          )
        end
      end

      Dir[Rails.root.join("db/seeds/*.rb")].sort.each { |f| load f }
    RUBY

    FileUtils.mkdir_p(File.join(db_dir, 'seeds'))
    File.write(File.join(db_dir, 'seeds/categories.rb'), <<~RUBY)
      Category.find_or_create_by!(name: "General")
    RUBY
  end

  after do
    FileUtils.rm_f(File.join(db_dir, 'seeds.rb'))
    FileUtils.rm_rf(File.join(db_dir, 'seeds'))
  end

  describe '#call' do
    subject(:result) { introspector.call }

    it 'analyzes seeds.rb' do
      seeds = result[:seeds_file]
      expect(seeds[:exists]).to be true
      expect(seeds[:uses_find_or_create]).to be true
      expect(seeds[:uses_create]).to be true
      expect(seeds[:uses_faker]).to be true
      expect(seeds[:environment_conditional]).to be true
      expect(seeds[:loads_directory]).to be true
    end

    it 'discovers seed files in db/seeds/' do
      expect(result[:seed_files].size).to eq(1)
      expect(result[:seed_files].first[:name]).to eq('categories')
    end

    it 'detects seeded models' do
      models = result[:models_seeded]
      expect(models).to include('User', 'Post', 'Category')
      expect(models).not_to include('Faker', 'Rails', 'Dir')
    end

    it 'does not return an error' do
      expect(result[:error]).to be_nil
    end
  end

  describe '#call with no seeds.rb' do
    let(:introspector) { described_class.new(app) }
    let(:result) { introspector.call }

    after do
      FileUtils.rm_f(File.join(db_dir, 'seeds.rb'))
      FileUtils.rm_rf(File.join(db_dir, 'seeds'))
    end

    it 'returns nil for seeds_file when db/seeds.rb does not exist' do
      FileUtils.rm_f(File.join(db_dir, 'seeds.rb'))
      FileUtils.rm_rf(File.join(db_dir, 'seeds'))
      expect(result[:seeds_file]).to be_nil
    end

    it 'returns empty array for seed_files when db/seeds/ does not exist' do
      FileUtils.rm_f(File.join(db_dir, 'seeds.rb'))
      FileUtils.rm_rf(File.join(db_dir, 'seeds'))
      expect(result[:seed_files]).to eq([])
    end

    it 'returns empty array for models_seeded when no seed files exist' do
      FileUtils.rm_f(File.join(db_dir, 'seeds.rb'))
      FileUtils.rm_rf(File.join(db_dir, 'seeds'))
      expect(result[:models_seeded]).to eq([])
    end
  end

  describe '#call with upsert, insert_all, and factory_bot' do
    let(:result) { introspector.call }

    before do
      File.write(File.join(db_dir, 'seeds.rb'), <<~RUBY)
        User.upsert(name: "Admin")
        Post.insert_all([{ title: "Test" }])
        FactoryBot.create(:user)
      RUBY
    end

    after do
      FileUtils.rm_f(File.join(db_dir, 'seeds.rb'))
      FileUtils.rm_rf(File.join(db_dir, 'seeds'))
    end

    it 'detects upsert, insert_all, and factory_bot usage' do
      seeds = result[:seeds_file]
      expect(seeds[:uses_upsert]).to be true
      expect(seeds[:uses_insert_all]).to be true
      expect(seeds[:uses_factory_bot]).to be true
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
