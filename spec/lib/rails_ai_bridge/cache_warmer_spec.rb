# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::CacheWarmer do
  let(:app) { Rails.application }

  before { RailsAiBridge::ContextProvider.reset! }
  after { RailsAiBridge::ContextProvider.reset! }

  describe '.warm' do
    it 'pre-populates the context cache for the given app' do
      allow(RailsAiBridge).to receive(:introspect).with(app).and_return({ schema: { tables: {} } })
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return('fp1')

      described_class.warm(app)

      # Second fetch should use cache, not re-introspect
      result = RailsAiBridge::ContextProvider.fetch(app)
      expect(result).to eq({ schema: { tables: {} } })
      expect(RailsAiBridge).to have_received(:introspect).with(app).once
    end

    it 'logs a warning when warming fails' do
      allow(RailsAiBridge::ContextProvider).to receive(:fetch).and_raise(StandardError, 'boom')
      logger = instance_double(ActiveSupport::Logger)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(logger).to receive(:warn)

      described_class.warm(app)

      expect(logger).to have_received(:warn).with(/cache warming failed.*boom/i)
    end

    it 'does not raise when warming fails' do
      allow(RailsAiBridge::ContextProvider).to receive(:fetch).and_raise(StandardError, 'boom')

      expect { described_class.warm(app) }.not_to raise_error
    end
  end

  describe '.warm_sections' do
    it 'pre-populates individual section caches' do
      schema_context = { app_name: 'Demo', schema: { tables: { 'users' => {} } } }
      introspector_instance = double('Introspector', call: schema_context)
      allow(RailsAiBridge::Introspector).to receive(:new).and_return(introspector_instance)
      allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).with(app).and_return('fp1')

      described_class.warm_sections(%i[schema], app)

      result = RailsAiBridge::ContextProvider.fetch_section(:schema, app)
      expect(result).to eq({ tables: { 'users' => {} } })
    end

    it 'silently handles errors for individual sections' do
      allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).and_raise(StandardError, 'boom')
      logger = instance_double(ActiveSupport::Logger)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(logger).to receive(:warn)

      expect { described_class.warm_sections(%i[schema models], app) }.not_to raise_error
    end
  end
end
