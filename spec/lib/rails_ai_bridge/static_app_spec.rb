# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::StaticApp do
  let(:root_path) { Pathname.new(Dir.mktmpdir('static-app-test-')) }

  after { FileUtils.remove_entry(root_path) if root_path&.exist? }

  describe '.new' do
    it 'accepts a string path' do
      app = described_class.new(root_path.to_s)
      expect(app.root).to eq(Pathname.new(root_path.to_s))
    end

    it 'accepts a Pathname' do
      app = described_class.new(root_path)
      expect(app.root).to eq(root_path)
    end
  end

  describe '#root' do
    it 'returns a Pathname' do
      app = described_class.new(root_path)
      expect(app.root).to be_a(Pathname)
    end
  end

  describe '#paths' do
    it 'returns conventional Rails paths rooted at root' do
      app = described_class.new(root_path)
      expect(app.paths['app/models']).to eq([root_path.join('app/models').to_s])
      expect(app.paths['app/controllers']).to eq([root_path.join('app/controllers').to_s])
    end

    it 'returns an array for each path key' do
      app = described_class.new(root_path)
      expect(app.paths['app/views']).to be_an(Array)
    end
  end

  describe '#config' do
    it 'returns a static config that reports api_only as false' do
      app = described_class.new(root_path)
      expect(app.config.api_only).to be(false)
    end

    it 'returns a static config that reports eager_load as false' do
      app = described_class.new(root_path)
      expect(app.config.eager_load).to be(false)
    end
  end

  describe '#eager_load!' do
    it 'is a no-op (does not raise)' do
      app = described_class.new(root_path)
      expect { app.eager_load! }.not_to raise_error
    end
  end

  describe '#class.name' do
    it 'reports StaticApp so app_name derivation works' do
      app = described_class.new(root_path)
      expect(app.class.name).to eq('RailsAiBridge::StaticApp')
    end
  end

  describe 'integration with AppScope' do
    it 'can be scoped via AppScope.with_app' do
      app = described_class.new(root_path)
      RailsAiBridge::AppScope.with_app(app) do
        expect(RailsAiBridge::AppScope.current_app).to eq(app)
      end
    end
  end

  describe 'integration with static-capable introspectors' do
    it 'runs SchemaIntrospector against a schema.rb file' do
      FileUtils.mkdir_p(root_path.join('db'))
      File.write(root_path.join('db/schema.rb'), <<~RUBY)
        ActiveRecord::Schema.define(version: 2024_01_01) do
          create_table "users", force: :cascade do |t|
            t.string "name"
            t.timestamps
          end
        end
      RUBY

      app = described_class.new(root_path)
      result = RailsAiBridge::Introspectors::SchemaIntrospector.new(app).call

      expect(result).to have_key(:tables)
      expect(result[:tables]).to have_key('users')
    end

    it 'runs GemIntrospector against a Gemfile.lock' do
      File.write(root_path.join('Gemfile.lock'), <<~TEXT)
        GEM
          remote: https://rubygems.org/
          specs:
            rails (7.1.0)
            pg (1.5.0)

        DEPENDENCIES
          rails (~> 7.1)
          pg
      TEXT

      app = described_class.new(root_path)
      result = RailsAiBridge::Introspectors::GemIntrospector.new(app).call

      expect(result).to have_key(:categories)
      expect(result[:categories]).to have_key('database')
    end
  end

  describe 'capability map' do
    it 'reports which introspectors are available in static mode' do
      expect(described_class::STATIC_CAPABLE).to include(:schema, :gems, :tests, :migrations)
    end

    it 'reports which introspectors require boot' do
      expect(described_class::BOOT_REQUIRED).to include(:models, :routes, :controllers)
    end

    it 'static_available? returns true for static-capable sections' do
      expect(described_class.static_available?(:schema)).to be(true)
      expect(described_class.static_available?(:models)).to be(false)
    end
  end
end
