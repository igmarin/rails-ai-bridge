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

    it 'returns queue adapter as a string' do
      expect(result[:queue_adapter]).to be_a(String)
    end

    it 'returns cable adapter as a string' do
      expect(result[:cable_adapter]).to be_a(String)
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
          middleware: ActionDispatch::MiddlewareStack.new,
          credentials: double('Credentials', config: {})
        )
      end

      before do
        FileUtils.mkdir_p(models_dir)
        File.write(models_dir.join('current.rb'), <<~RUBY)
          class Current < ActiveSupport::CurrentAttributes
            attribute :account
          end
        RUBY
      end

      after { FileUtils.rm_rf(app_root) }

      it 'detects CurrentAttributes outside conventional app/models' do
        expect(described_class.new(custom_app).call[:current_attributes]).to include('Current')
      end
    end

    context 'with cache_store as an Array' do
      let(:custom_config) do
        double('ApplicationConfig', cache_store: [:redis_cache, 'redis://localhost'],
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC')
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns the first element as the cache store name' do
        expect(described_class.new(custom_app).call[:cache_store]).to eq('redis_cache')
      end
    end

    context 'with cache_store as a non-Symbol non-Array object' do
      let(:store_obj) { Object.new }
      let(:custom_config) do
        double('ApplicationConfig', cache_store: store_obj,
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC')
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns the class name of the store object' do
        expect(described_class.new(custom_app).call[:cache_store]).to eq(store_obj.class.name)
      end
    end

    context 'when cache_store raises an error' do
      let(:custom_config) do
        double('ApplicationConfig', time_zone: 'UTC',
                                    session_store: ActionDispatch::Session::CookieStore)
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      before do
        allow(custom_config).to receive(:cache_store).and_raise(StandardError, 'boom')
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(false)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns unknown for cache_store' do
        expect(described_class.new(custom_app).call[:cache_store]).to eq('unknown')
      end
    end

    context 'when session_store is nil' do
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: nil, time_zone: 'UTC')
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns nil for session_store' do
        expect(described_class.new(custom_app).call[:session_store]).to be_nil
      end
    end

    context 'when session_store raises an error' do
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store, time_zone: 'UTC')
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      before do
        allow(custom_config).to receive(:session_store).and_raise(StandardError, 'boom')
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(false)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns unknown for session_store' do
        expect(described_class.new(custom_app).call[:session_store]).to eq('unknown')
      end
    end

    context 'when app does not respond to active_job' do
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC')
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      before do
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(false)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns unknown for queue_adapter' do
        expect(described_class.new(custom_app).call[:queue_adapter]).to eq('unknown')
      end
    end

    context 'when queue_adapter is a Symbol' do
      let(:active_job_config) { double('ActiveJobConfig', queue_adapter: :sidekiq) }
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC',
                                    active_job: active_job_config)
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      before do
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(true)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns the symbol as a string' do
        expect(described_class.new(custom_app).call[:queue_adapter]).to eq('sidekiq')
      end
    end

    context 'when app does not respond to action_cable' do
      let(:active_job_config) { double('ActiveJobConfig', queue_adapter: :sidekiq) }
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC',
                                    active_job: active_job_config)
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      before do
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(true)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns unknown for cable_adapter' do
        expect(described_class.new(custom_app).call[:cable_adapter]).to eq('unknown')
      end
    end

    context 'when cable_adapter is a Symbol' do
      let(:active_job_config) { double('ActiveJobConfig', queue_adapter: :sidekiq) }
      let(:cable_config) { double('CableConfig', adapter: :redis) }
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC',
                                    active_job: active_job_config, action_cable: cable_config)
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      before do
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(true)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(true)
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns the symbol as a string' do
        expect(described_class.new(custom_app).call[:cable_adapter]).to eq('redis')
      end
    end

    context 'when middleware raises an error' do
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC')
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      before do
        allow(custom_app).to receive(:middleware).and_raise(StandardError, 'boom')
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(false)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns empty array for middleware_stack' do
        expect(described_class.new(custom_app).call[:middleware_stack]).to eq([])
      end
    end

    context 'when config/initializers does not exist' do
      let(:app_root) { Pathname.new(Dir.mktmpdir('no-init')) }
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC')
      end
      let(:custom_app) do
        double('Rails::Application', root: app_root,
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      before do
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(false)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
      end

      after { FileUtils.rm_rf(app_root) }

      it 'returns empty array for initializers' do
        expect(described_class.new(custom_app).call[:initializers]).to eq([])
      end
    end

    context 'when credentials do not respond to config' do
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC')
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials'))
      end

      before do
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(false)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
        RailsAiBridge.configuration.expose_credentials_key_names = true
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns empty array for credentials_keys' do
        expect(described_class.new(custom_app).call[:credentials_keys]).to eq([])
      end
    end

    context 'when credentials raise an error' do
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: ActionDispatch::Session::CookieStore, time_zone: 'UTC')
      end
      let(:custom_app) do
        double('Rails::Application', root: Pathname.new(Dir.mktmpdir),
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials'))
      end

      before do
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(false)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
        allow(custom_app).to receive(:credentials).and_raise(StandardError, 'boom')
        RailsAiBridge.configuration.expose_credentials_key_names = true
      end

      after { FileUtils.rm_rf(custom_app.root) }

      it 'returns empty array for credentials_keys on error' do
        expect(described_class.new(custom_app).call[:credentials_keys]).to eq([])
      end
    end

    context 'when app.config.time_zone raises an error' do
      let(:app_root) { Pathname.new(Dir.mktmpdir) }
      let(:custom_config) do
        double('ApplicationConfig', cache_store: :memory_store,
                                    session_store: ActionDispatch::Session::CookieStore)
      end
      let(:custom_app) do
        double('Rails::Application', root: app_root,
                                     paths: { 'app/models' => [] }, config: custom_config,
                                     middleware: ActionDispatch::MiddlewareStack.new,
                                     credentials: double('Credentials', config: {}))
      end

      before do
        allow(custom_config).to receive(:time_zone).and_raise(StandardError, 'tz boom')
        allow(custom_config).to receive(:respond_to?).with(:active_job).and_return(false)
        allow(custom_config).to receive(:respond_to?).with(:action_cable).and_return(false)
      end

      after { FileUtils.rm_rf(app_root) }

      it 'returns error hash' do
        expect(described_class.new(custom_app).call[:error]).to eq('tz boom')
      end
    end
  end
end
