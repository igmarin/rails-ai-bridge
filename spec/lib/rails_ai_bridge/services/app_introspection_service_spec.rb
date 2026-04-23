# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/services/app_introspection_service'
require 'rails_ai_bridge/introspector'

RSpec.describe RailsAiBridge::Services::AppIntrospectionService do
  let(:app) { double('Rails App') }
  let(:introspector_class) { RailsAiBridge::Introspector }
  let(:introspector_instance) { instance_double(RailsAiBridge::Introspector) }

  describe '.call' do
    it 'creates introspector and calls it with app' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: nil).and_return({ test: 'data' })

      result = described_class.call(app)

      expect(result).to be_a(RailsAiBridge::Service::Result)
      expect(result.success?).to be(true)
      expect(result.data).to eq({ test: 'data' })
    end

    it 'passes only parameter to introspector' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: %i[models routes]).and_return({})

      result = described_class.call(app, only: %i[models routes])
      expect(result.success?).to be(true)
    end

    it 'handles introspector errors gracefully' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).and_raise('Introspection failed')

      result = described_class.call(app)

      expect(result.failure?).to be(true)
      expect(result.errors).to eq(['Introspection failed'])
    end
  end

  describe '#call' do
    subject { described_class.new(app) }

    it 'delegates to introspector with default class' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: [:models]).and_return({ models: [] })

      result = subject.call(only: [:models])

      expect(result.success?).to be(true)
      expect(result.data).to eq({ models: [] })
    end

    it 'allows custom introspector class' do
      custom_introspector = double('CustomIntrospector')
      allow(custom_introspector).to receive(:new).with(app).and_return(custom_introspector)
      allow(custom_introspector).to receive(:call).with(only: nil).and_return({ custom: true })

      service = described_class.new(app, introspector_class: custom_introspector)
      result = service.call

      expect(result.data).to eq({ custom: true })
    end
  end

  describe 'introspection result validation' do
    it 'fails when introspector returns a non-Hash' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: nil).and_return('not a hash')

      result = described_class.call(app)

      expect(result.failure?).to be(true)
      expect(result.errors).to eq(['Introspector must return a Hash'])
    end

    it 'fails when introspector returns top-level :error' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: nil).and_return({ error: 'boom' })

      result = described_class.call(app)

      expect(result.failure?).to be(true)
      expect(result.errors).to eq(['Introspector returned error: boom'])
    end

    it 'fails when a nested payload is a Hash with :error' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: nil).and_return({
                                                                                  models: { error: 'schema missing' },
                                                                                  routes: {}
                                                                                })

      result = described_class.call(app)

      expect(result.failure?).to be(true)
      expect(result.errors).to eq(['models: schema missing'])
    end

    it 'aggregates multiple nested introspector errors' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: nil).and_return({
                                                                                  models: { error: 'a' },
                                                                                  routes: { error: 'b' }
                                                                                })

      result = described_class.call(app)

      expect(result.failure?).to be(true)
      expect(result.errors).to contain_exactly('models: a', 'routes: b')
    end

    it 'succeeds when nested values are Hashes without :error' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: nil).and_return({
                                                                                  models: { list: ['User'] },
                                                                                  routes: {}
                                                                                })

      result = described_class.call(app)

      expect(result.success?).to be(true)
      expect(result.data[:models]).to eq({ list: ['User'] })
    end

    it 'ignores non-Hash nested values for error scanning' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: nil).and_return({
                                                                                  models: ['User'],
                                                                                  routes: {}
                                                                                })

      result = described_class.call(app)

      expect(result.success?).to be(true)
    end
  end

  describe 'result format' do
    it 'returns Service::Result with proper structure' do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).and_return({
                                                                  models: ['User'],
                                                                  routes: {}
                                                                })

      result = described_class.call(app)

      expect(result).to be_a(RailsAiBridge::Service::Result)
      expect(result.success?).to be(true)
      expect(result.data[:models]).to eq(['User'])
      expect(result.data[:routes]).to eq({})
      expect(result.errors).to be_empty
    end
  end
end
