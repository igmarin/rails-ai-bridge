# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::ContextProvider do
  let(:app) { Rails.application }
  let(:fingerprint) { 'fingerprint-1' }
  let(:context) { { schema: { tables: {} } } }

  before do
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  describe '.reset!' do
    it 'reinitializes the synchronization mutex used by the cache' do
      described_class.reset!

      mutex = described_class.instance_variable_get(:@mutex)

      expect(mutex).to be_a(Mutex)
    end
  end

  describe '.fetch' do
    it 'builds context on first request' do
      allow(RailsAiBridge).to receive(:introspect).with(app).and_return(context)
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint)

      result = described_class.fetch(app)

      expect(result).to eq(context)
      expect(RailsAiBridge).to have_received(:introspect).with(app).once
    end

    it 'reuses cached context while ttl is valid and fingerprint is unchanged' do
      allow(RailsAiBridge).to receive(:introspect).with(app).and_return(context)
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint)

      first = described_class.fetch(app)
      second = described_class.fetch(app)

      expect(first).to eq(context)
      expect(second).to eq(context)
      expect(RailsAiBridge).to have_received(:introspect).with(app).once
    end

    it 'rebuilds context when the fingerprint changes before ttl expiry' do
      allow(RailsAiBridge).to receive(:introspect).with(app).and_return(context, { routes: { total_routes: 3 } })
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return('fingerprint-1', 'fingerprint-2')

      first = described_class.fetch(app)

      # Invalidate fingerprint cache so the next fetch sees the new fingerprint
      RailsAiBridge::Fingerprinter::CachedSnapshot.invalidate!(app)
      second = described_class.fetch(app)

      expect(first).to eq(context)
      expect(second).to eq({ routes: { total_routes: 3 } })
      expect(RailsAiBridge).to have_received(:introspect).with(app).twice
      expect(RailsAiBridge::Fingerprinter).to have_received(:snapshot).with(app).twice
    end
  end

  describe '.fetch_section' do
    it 'builds only the requested section when it is not cached yet' do
      schema_context = { app_name: 'Demo', schema: { tables: { 'users' => {} } } }

      allow(RailsAiBridge).to receive(:introspect).and_call_original
      introspector_instance = double('Introspector', call: schema_context)
      allow(RailsAiBridge::Introspector).to receive(:new).and_return(introspector_instance)
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint)

      result = described_class.fetch_section(:schema, app)

      expect(result).to eq(schema_context[:schema])
    end

    it 'reuses the cached section while ttl is valid and fingerprint is unchanged' do
      schema_context = { app_name: 'Demo', schema: { tables: { 'users' => {} } } }

      introspector_instance = double('Introspector', call: schema_context)
      allow(RailsAiBridge::Introspector).to receive(:new).and_return(introspector_instance)
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return(fingerprint)

      first = described_class.fetch_section(:schema, app)
      second = described_class.fetch_section(:schema, app)

      expect(first).to eq(schema_context[:schema])
      expect(second).to eq(schema_context[:schema])
    end
  end

  describe 'fork safety' do
    it 'uses a stable cache key that does not depend on object_id' do
      app1 = double('App1', class: double(name: 'Rails::Application'))
      app2 = double('App2', class: double(name: 'Rails::Application'))
      allow(RailsAiBridge).to receive(:introspect).and_return(context)
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).and_return(fingerprint)
      allow(RailsAiBridge::Fingerprinter::CachedSnapshot).to receive(:fetch).and_return(fingerprint)

      described_class.fetch(app1)

      # A new app object with the same class name and env should hit the same cache key
      result = described_class.fetch(app2)

      expect(result).to eq(context)
      # introspect should only be called once because both apps share the cache key
      expect(RailsAiBridge).to have_received(:introspect).once
    end

    it 'cache key includes class name and Rails env' do
      app_double = double('App', class: double(name: 'MyApp::Application'))

      key = described_class.send(:cache_key, app_double)

      expect(key).to include('MyApp::Application')
      expect(key).to include(Rails.env.to_s)
    end
  end
end
