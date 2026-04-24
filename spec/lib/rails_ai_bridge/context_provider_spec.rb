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
      allow(RailsAiBridge::Fingerprinter).to receive(:compute).with(app).and_call_original

      first = described_class.fetch(app)
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
end
