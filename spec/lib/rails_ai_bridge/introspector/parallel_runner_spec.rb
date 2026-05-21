# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspector::ParallelRunner do
  let(:app) { Rails.application }

  around do |example|
    orig_pool    = RailsAiBridge.configuration.parallel_pool_size
    orig_timeout = RailsAiBridge.configuration.parallel_timeout_seconds
    example.run
  ensure
    RailsAiBridge.configuration.parallel_pool_size       = orig_pool
    RailsAiBridge.configuration.parallel_timeout_seconds = orig_timeout
  end

  describe '.call' do
    let(:schema_class) { class_double(RailsAiBridge::Introspectors::SchemaIntrospector) }
    let(:model_class)  { class_double(RailsAiBridge::Introspectors::ModelIntrospector) }

    it 'runs introspectors and returns results keyed by name' do
      schema_instance = double('SchemaIntrospector', call: { tables: {} })
      model_instance  = double('ModelIntrospector',  call: { 'User' => {} })
      introspectors   = { schema: schema_class, models: model_class }

      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)
      allow(model_class).to receive(:new).with(app).and_return(model_instance)

      result = described_class.call(introspectors, app)

      expect(result[:schema]).to eq({ tables: {} })
      expect(result[:models]).to eq({ 'User' => {} })
    end

    it 'captures errors per introspector without raising' do
      schema_instance = double('SchemaIntrospector')
      allow(schema_instance).to receive(:call).and_raise(StandardError, 'schema boom')
      introspectors = { schema: schema_class }
      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)

      result = described_class.call(introspectors, app)

      expect(result[:schema]).to eq({ error: 'schema boom' })
    end

    it 'handles mixed success and failure' do
      schema_instance = double('SchemaIntrospector', call: { tables: {} })
      model_instance  = double('ModelIntrospector')
      allow(model_instance).to receive(:call).and_raise(StandardError, 'model fail')
      introspectors = { schema: schema_class, models: model_class }

      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)
      allow(model_class).to receive(:new).with(app).and_return(model_instance)

      result = described_class.call(introspectors, app)

      expect(result[:schema]).to eq({ tables: {} })
      expect(result[:models]).to eq({ error: 'model fail' })
    end

    it 'returns empty hash for empty introspector list' do
      expect(described_class.call({}, app)).to eq({})
    end

    it 'works with single introspector' do
      schema_instance = double('SchemaIntrospector', call: { tables: {} })
      introspectors   = { schema: schema_class }
      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)

      result = described_class.call(introspectors, app)

      expect(result[:schema]).to eq({ tables: {} })
    end

    it 'returns a timed_out error when the introspector exceeds the timeout' do
      slow_class = Class.new do
        def initialize(_app); end
        def call = sleep(5)
      end
      RailsAiBridge.configuration.parallel_timeout_seconds = 0.05

      result = described_class.call({ slow: slow_class }, app)

      expect(result[:slow]).to have_key(:error)
      expect(result[:slow][:error]).to include('timed out')
    end

    it 'respects parallel_pool_size from configuration' do
      RailsAiBridge.configuration.parallel_pool_size = 2
      schema_instance = double('SchemaIntrospector', call: {})
      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)

      pool_size_used = nil
      allow(Concurrent::FixedThreadPool).to receive(:new).and_wrap_original do |orig, size, *args|
        pool_size_used = size
        orig.call(size, *args)
      end

      described_class.call({ schema: schema_class }, app)

      # 1 introspector, pool_size config = 2 → min(1, 2) = 1
      expect(pool_size_used).to eq(1)
    end

    it 'respects a larger parallel_pool_size with multiple introspectors' do
      RailsAiBridge.configuration.parallel_pool_size = 4
      model_instance  = double('ModelIntrospector',  call: {})
      schema_instance = double('SchemaIntrospector', call: {})
      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)
      allow(model_class).to receive(:new).with(app).and_return(model_instance)

      pool_size_used = nil
      allow(Concurrent::FixedThreadPool).to receive(:new).and_wrap_original do |orig, size, *args|
        pool_size_used = size
        orig.call(size, *args)
      end

      described_class.call({ schema: schema_class, models: model_class }, app)

      # 2 introspectors, pool_size config = 4 → min(2, 4) = 2
      expect(pool_size_used).to eq(2)
    end

    it 'shuts down the pool after execution' do
      schema_instance = double('SchemaIntrospector', call: {})
      allow(schema_class).to receive(:new).with(app).and_return(schema_instance)

      real_pool = nil
      allow(Concurrent::FixedThreadPool).to receive(:new).and_wrap_original do |orig, size, *args|
        real_pool = orig.call(size, *args)
        allow(real_pool).to receive(:shutdown).and_call_original
        real_pool
      end

      described_class.call({ schema: schema_class }, app)

      expect(real_pool).to have_received(:shutdown)
    end
  end

  describe '.available?' do
    it 'returns true when concurrent-ruby is installed' do
      expect(described_class.available?).to be(true)
    end

    it 'returns false when Concurrent::Future is not defined' do
      hide_const('Concurrent::Future')

      expect(described_class.available?).to be(false)
    end

    context 'when ActiveRecord connection pool is too small' do
      it 'returns false when pool size is 1' do
        pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool, size: 1)
        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(pool)

        expect(described_class.available?).to be(false)
      end

      it 'returns true when pool size is 2 or more' do
        pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool, size: 2)
        allow(ActiveRecord::Base).to receive(:connection_pool).and_return(pool)

        expect(described_class.available?).to be(true)
      end

      it 'returns true when AR pool size check raises' do
        allow(ActiveRecord::Base).to receive(:connection_pool).and_raise(StandardError)

        expect(described_class.available?).to be(true)
      end
    end
  end
end
