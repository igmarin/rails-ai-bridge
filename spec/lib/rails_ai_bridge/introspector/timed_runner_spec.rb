# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspector::TimedRunner do
  let(:app) { Rails.application }

  describe '.call' do
    context 'when the introspector succeeds' do
      it 'returns the introspector result' do
        klass = Class.new do
          def initialize(_app); end
          def call = { tables: { users: {} } }
        end

        result = described_class.call(klass, app)

        expect(result[:result]).to eq({ tables: { users: {} } })
      end

      it 'returns a non-negative duration_ms' do
        klass = Class.new do
          def initialize(_app); end
          def call = {}
        end

        result = described_class.call(klass, app)

        expect(result[:duration_ms]).to be >= 0
      end

      it 'returns duration_ms as a Float' do
        klass = Class.new do
          def initialize(_app); end
          def call = {}
        end

        result = described_class.call(klass, app)

        expect(result[:duration_ms]).to be_a(Float)
      end
    end

    context 'when the introspector raises' do
      it 'captures the error and returns an error hash' do
        klass = Class.new do
          def initialize(_app); end
          def call = raise(StandardError, 'boom')
        end

        result = described_class.call(klass, app)

        expect(result[:result]).to eq({ error: 'boom' })
      end

      it 'still returns a duration_ms on error' do
        klass = Class.new do
          def initialize(_app); end
          def call = raise(StandardError, 'oops')
        end

        result = described_class.call(klass, app)

        expect(result[:duration_ms]).to be >= 0
      end
    end

    it 'instantiates the class with the app' do
      klass = Class.new do
        attr_reader :app

        def initialize(app)
          @app = app
        end

        def call = { app: @app.object_id }
      end

      result = described_class.call(klass, app)

      expect(result[:result][:app]).to eq(app.object_id)
    end
  end
end
