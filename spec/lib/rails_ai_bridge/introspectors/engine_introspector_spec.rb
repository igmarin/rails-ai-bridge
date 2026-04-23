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
end
