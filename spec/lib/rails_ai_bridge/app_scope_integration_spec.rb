# frozen_string_literal: true

require 'spec_helper'

# Consumer-level specs proving that key subsystems resolve the app through
# AppScope.current_app instead of hardcoding Rails.application.
RSpec.describe 'AppScope consumer integration' do
  let(:fake_app) do
    instance_double(Rails::Application,
                    root: Pathname.new(Dir.mktmpdir('app-scope-consumer-')),
                    config: double('Rails::Configuration', eager_load: true),
                    eager_load!: nil,
                    paths: {})
  end

  after do
    FileUtils.remove_entry(fake_app.root) if fake_app.root&.exist?
    RailsAiBridge::AppScope.clear_app
  end

  describe 'BaseTool.rails_app' do
    it 'returns the scoped app inside with_app' do
      RailsAiBridge::AppScope.with_app(fake_app) do
        expect(RailsAiBridge::Tools::BaseTool.rails_app).to eq(fake_app)
      end
    end

    it 'falls back to Rails.application outside with_app' do
      expect(RailsAiBridge::Tools::BaseTool.rails_app).to eq(Rails.application)
    end
  end

  describe 'ContextProvider.fetch' do
    it 'passes the scoped app to Introspector' do
      introspector = instance_double(RailsAiBridge::Introspector, call: {})
      allow(RailsAiBridge::Introspector).to receive(:new).with(fake_app).and_return(introspector)

      RailsAiBridge::AppScope.with_app(fake_app) do
        RailsAiBridge::ContextProvider.reset!
        RailsAiBridge::ContextProvider.fetch
      end
    end
  end

  describe 'ContextProvider.fetch_section' do
    it 'passes the scoped app to Introspector' do
      introspector = instance_double(RailsAiBridge::Introspector, call: { models: {} })
      allow(RailsAiBridge::Introspector).to receive(:new).with(fake_app).and_return(introspector)
      allow(introspector).to receive(:call).with(only: [:models]).and_return({ models: {} })

      RailsAiBridge::AppScope.with_app(fake_app) do
        RailsAiBridge::ContextProvider.reset!
        RailsAiBridge::ContextProvider.fetch_section(:models)
      end
    end
  end

  describe 'CacheWarmer.warm' do
    it 'uses the scoped app when no explicit app is passed' do
      expect(RailsAiBridge::ContextProvider).to receive(:fetch).with(fake_app)
      RailsAiBridge::AppScope.with_app(fake_app) do
        RailsAiBridge::CacheWarmer.warm
      end
    end
  end

  describe 'Doctor#initialize' do
    it 'uses the scoped app when no explicit app is passed' do
      doctor = nil
      RailsAiBridge::AppScope.with_app(fake_app) do
        doctor = RailsAiBridge::Doctor.new
      end
      expect(doctor.app).to eq(fake_app)
    end
  end

  describe 'Watcher#initialize' do
    it 'uses the scoped app when no explicit app is passed' do
      stub_const('Listen', Module.new) unless defined?(Listen)

      watcher = nil
      RailsAiBridge::AppScope.with_app(fake_app) do
        watcher = RailsAiBridge::Watcher.new
      end
      expect(watcher.app).to eq(fake_app)
    end
  end

  describe 'RailsAiBridge.introspect' do
    it 'passes the scoped app to Introspector' do
      introspector = instance_double(RailsAiBridge::Introspector, call: {})
      allow(RailsAiBridge::Introspector).to receive(:new).with(fake_app).and_return(introspector)

      RailsAiBridge::AppScope.with_app(fake_app) do
        RailsAiBridge.introspect
      end
    end
  end

  describe 'Resources.read_view_resource' do
    it 'returns error hash when app is nil' do
      # Temporarily clear all app resolution
      allow(RailsAiBridge::AppScope).to receive(:current_app).and_return(nil)
      result = RailsAiBridge::Resources.send(:read_view_resource, 'users/index.html.erb')
      expect(result).to eq({ error: 'No Rails application available' })
    end
  end
end
