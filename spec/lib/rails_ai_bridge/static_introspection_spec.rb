# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Static mode introspection' do
  let(:root_path) { Pathname.new(Dir.mktmpdir('static-introspect-')) }
  let(:static_app) { RailsAiBridge::StaticApp.new(root_path) }

  after { FileUtils.remove_entry(root_path) if root_path&.exist? }

  describe 'RailsAiBridge::Introspector with StaticApp' do
    it 'runs only static-capable introspectors and returns metadata' do
      # Create a schema.rb so the schema introspector has something to read
      FileUtils.mkdir_p(root_path.join('db'))
      File.write(root_path.join('db/schema.rb'), <<~RUBY)
        ActiveRecord::Schema.define(version: 2024_01_01) do
          create_table "users", force: :cascade do |t|
            t.string "name"
          end
        end
      RUBY

      result = RailsAiBridge::Introspector.new(static_app).call(only: %i[schema models routes])

      # Static-capable introspector should produce real results
      expect(result).to have_key(:schema)
      expect(result[:schema]).to have_key(:tables)

      # Boot-required introspectors should report unavailable
      expect(result).to have_key(:models)
      expect(result[:models]).to have_key(:error)
      expect(result[:models][:error]).to match(/not available without boot/i)

      expect(result).to have_key(:routes)
      expect(result[:routes]).to have_key(:error)
      expect(result[:routes][:error]).to match(/not available without boot/i)
    end

    it 'includes metadata with app_name derived from StaticApp class' do
      result = RailsAiBridge::Introspector.new(static_app).call(only: %i[schema])

      expect(result[:app_name]).to eq('RailsAiBridge')
    end

    it 'includes a static_mode flag in metadata' do
      result = RailsAiBridge::Introspector.new(static_app).call(only: %i[schema])

      expect(result[:static_mode]).to be(true)
    end
  end

  describe 'RailsAiBridge.introspect with StaticApp via AppScope' do
    it 'works through the public API with AppScope' do
      FileUtils.mkdir_p(root_path.join('db'))
      File.write(root_path.join('db/schema.rb'), <<~RUBY)
        ActiveRecord::Schema.define(version: 2024_01_01) do
          create_table "posts", force: :cascade do |t|
            t.string "title"
          end
        end
      RUBY

      RailsAiBridge::AppScope.with_app(static_app) do
        result = RailsAiBridge.introspect(only: %i[schema])
        expect(result[:schema]).to have_key(:tables)
        expect(result[:schema][:tables]).to have_key('posts')
      end
    end
  end
end
