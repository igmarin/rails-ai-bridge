# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ConfigIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    around do |example|
      saved = RailsAiBridge.configuration.expose_credentials_key_names
      example.run
    ensure
      RailsAiBridge.configuration.expose_credentials_key_names = saved
    end

    it 'returns cache store as a known value' do
      expect(result[:cache_store]).to be_a(String)
      expect(result[:cache_store]).not_to be_empty
    end

    it 'returns session store' do
      expect(result).to have_key(:session_store)
    end

    it 'returns timezone as a non-empty string' do
      expect(result[:timezone]).to be_a(String)
      expect(result[:timezone]).not_to be_empty
    end

    it 'returns middleware stack as non-empty array of strings' do
      expect(result[:middleware_stack]).to be_an(Array)
      expect(result[:middleware_stack]).not_to be_empty
      expect(result[:middleware_stack]).to all(be_a(String))
    end

    it 'returns initializers as array of strings' do
      expect(result[:initializers]).to be_an(Array)
      result[:initializers].each do |init|
        expect(init).to be_a(String)
        expect(init).to end_with('.rb')
      end
    end

    it 'does not expose credentials_keys by default' do
      RailsAiBridge.configuration.expose_credentials_key_names = false
      expect(result).not_to have_key(:credentials_keys)
    end

    it 'returns credentials keys as array when expose_credentials_key_names is true' do
      RailsAiBridge.configuration.expose_credentials_key_names = true
      expect(result[:credentials_keys]).to be_an(Array)
    end

    it 'returns current attributes as array' do
      expect(result[:current_attributes]).to be_an(Array)
    end

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    context 'with a CurrentAttributes model' do
      let(:fixture_model) { Rails.root.join('app/models/current.rb').to_s }

      before do
        File.write(fixture_model, <<~RUBY)
          class Current < ActiveSupport::CurrentAttributes
            attribute :user
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it 'detects CurrentAttributes classes' do
        expect(result[:current_attributes]).to include('Current')
      end
    end

    context 'with configured model paths' do
      let(:app_root) { Pathname.new(Dir.mktmpdir('rails-ai-bridge-config')) }
      let(:models_dir) { app_root.join('domain/models') }
      let(:custom_config) do
        double(
          'ApplicationConfig',
          cache_store: :memory_store,
          session_store: ActionDispatch::Session::CookieStore,
          time_zone: 'UTC'
        )
      end
      let(:custom_app) do
        double(
          'Rails::Application',
          root: app_root,
          paths: { 'app/models' => [models_dir.to_s] },
          config: custom_config,
          middleware: [],
          credentials: double('Credentials', config: {})
        )
      end

      after { FileUtils.rm_rf(app_root) }

      before do
        FileUtils.mkdir_p(models_dir)
        File.write(models_dir.join('current.rb'), <<~RUBY)
          class Current < ActiveSupport::CurrentAttributes
            attribute :account
          end
        RUBY
      end

      it 'detects CurrentAttributes outside conventional app/models' do
        expect(described_class.new(custom_app).call[:current_attributes]).to include('Current')
      end
    end
  end
end
