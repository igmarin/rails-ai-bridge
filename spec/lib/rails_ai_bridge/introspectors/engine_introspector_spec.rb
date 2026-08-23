# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::EngineIntrospector do
  let(:app) { Rails.application }
  let(:introspector) { described_class.new(app) }

  describe '#call' do
    subject(:result) { introspector.call }

    context 'with mounted engines in routes' do
      let(:routes_path) { File.join(app.root.to_s, 'config/routes.rb') }
      let(:original_content) { File.exist?(routes_path) ? File.read(routes_path) : nil }
      let(:original_backup) { original_content }

      before do
        original_backup
        File.write(routes_path, <<~RUBY)
          Rails.application.routes.draw do
            mount Sidekiq::Web => "/sidekiq"
            mount Flipper::UI, at: "/flipper"
            mount PgHero::Engine, at: "/pghero"

            resources :posts
          end
        RUBY
      end

      after do
        if original_backup
          File.write(routes_path, original_backup)
        else
          FileUtils.rm_f(routes_path)
        end
        app.reload_routes!
      end

      it 'discovers mounted engines' do
        engines = result[:mounted_engines]
        names = engines.pluck(:engine)
        expect(names).to include('Sidekiq::Web', 'Flipper::UI', 'PgHero::Engine')
      end

      it 'includes path for each engine' do
        sidekiq = result[:mounted_engines].find { |e| e[:engine] == 'Sidekiq::Web' }
        expect(sidekiq[:path]).to eq('/sidekiq')
      end

      it 'includes description for known engines' do
        sidekiq = result[:mounted_engines].find { |e| e[:engine] == 'Sidekiq::Web' }
        expect(sidekiq[:description]).to include('Sidekiq')
        expect(sidekiq[:category]).to eq('admin')
      end

      it 'includes description for Flipper' do
        flipper = result[:mounted_engines].find { |e| e[:engine] == 'Flipper::UI' }
        expect(flipper[:description]).to include('feature flag')
      end
    end

    context 'with no mounted engines' do
      let(:routes_path) { File.join(app.root.to_s, 'config/routes.rb') }
      let(:original_content) { File.exist?(routes_path) ? File.read(routes_path) : nil }
      let(:original_backup) { original_content }

      before do
        original_backup
        File.write(routes_path, <<~RUBY)
          Rails.application.routes.draw do
            resources :posts
          end
        RUBY
      end

      after do
        if original_backup
          File.write(routes_path, original_backup)
        else
          FileUtils.rm_f(routes_path)
        end
        app.reload_routes!
      end

      it 'returns empty array' do
        expect(result[:mounted_engines]).to eq([])
      end
    end

    it 'discovers loaded Rails engines' do
      engines = result[:rails_engines]
      expect(engines).to be_an(Array)
    end

    it 'does not return an error' do
      expect(result[:error]).to be_nil
    end
  end

  describe '#call with no routes.rb' do
    let(:app_root) { Pathname.new(Dir.mktmpdir('no-routes')) }
    let(:custom_app) { double('Rails::Application', root: app_root) }
    let(:result) { described_class.new(custom_app).call }

    after { FileUtils.rm_rf(app_root) }

    it 'returns empty array for mounted_engines when routes.rb does not exist' do
      expect(result[:mounted_engines]).to eq([])
    end
  end

  describe '#call with mount without path (fallback regex)' do
    let(:app_root) { Pathname.new(Dir.mktmpdir('engine-fallback')) }
    let(:routes_path) { app_root.join('config/routes.rb') }
    let(:custom_app) { double('Rails::Application', root: app_root) }
    let(:result) { described_class.new(custom_app).call }

    before do
      FileUtils.mkdir_p(app_root.join('config'))
      File.write(routes_path, <<~RUBY)
        Rails.application.routes.draw do
          mount Sidekiq::Web
          resources :posts
        end
      RUBY
    end

    after { FileUtils.rm_rf(app_root) }

    it 'discovers engines via fallback regex with unknown path' do
      sidekiq = result[:mounted_engines].find { |e| e[:engine] == 'Sidekiq::Web' }
      expect(sidekiq).not_to be_nil
      expect(sidekiq[:path]).to eq('unknown')
      expect(sidekiq[:category]).to eq('admin')
    end
  end

  describe '#call with unknown engine (not in KNOWN_ENGINES)' do
    let(:app_root) { Pathname.new(Dir.mktmpdir('engine-unknown')) }
    let(:routes_path) { app_root.join('config/routes.rb') }
    let(:custom_app) { double('Rails::Application', root: app_root) }
    let(:result) { described_class.new(custom_app).call }

    before do
      FileUtils.mkdir_p(app_root.join('config'))
      File.write(routes_path, <<~RUBY)
        Rails.application.routes.draw do
          mount SomeCustom::Engine => "/custom"
        end
      RUBY
    end

    after { FileUtils.rm_rf(app_root) }

    it 'includes engine without category or description' do
      engine = result[:mounted_engines].find { |e| e[:engine] == 'SomeCustom::Engine' }
      expect(engine).not_to be_nil
      expect(engine).not_to have_key(:category)
      expect(engine).not_to have_key(:description)
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
