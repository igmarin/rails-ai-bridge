# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Service::Result do
  describe '#initialize' do
    it 'creates a success result' do
      result = described_class.new(true, data: 'test_data')
      expect(result.success).to be(true)
      expect(result.data).to eq('test_data')
      expect(result.errors).to eq([])
    end

    it 'creates a failure result' do
      result = described_class.new(false, errors: %w[error1 error2])
      expect(result.success).to be(false)
      expect(result.data).to be_nil
      expect(result.errors).to eq(%w[error1 error2])
    end

    it 'accepts metadata' do
      metadata = { timestamp: Time.zone.now, request_id: '123' }
      result = described_class.new(true, metadata: metadata)
      expect(result.metadata).to eq(metadata)
    end

    it 'converts single error to array' do
      result = described_class.new(false, errors: 'single_error')
      expect(result.errors).to eq(['single_error'])
    end
  end

  describe '#success? and #failure?' do
    it 'returns true for success? when successful' do
      result = described_class.new(true)
      expect(result.success?).to be(true)
      expect(result.failure?).to be(false)
    end

    it 'returns true for failure? when failed' do
      result = described_class.new(false)
      expect(result.success?).to be(false)
      expect(result.failure?).to be(true)
    end
  end

  describe '#on_success and #on_failure' do
    it 'executes block on success' do
      result = described_class.new(true, data: 'test')
      called = false
      result.on_success { called = true }
      expect(called).to be(true)
    end

    it 'does not execute block on success when failed' do
      result = described_class.new(false)
      called = false
      result.on_success { called = true }
      expect(called).to be(false)
    end

    it 'executes block on failure' do
      result = described_class.new(false, errors: ['error'])
      called = false
      result.on_failure { called = true }
      expect(called).to be(true)
    end

    it 'does not execute block on failure when succeeded' do
      result = described_class.new(true)
      called = false
      result.on_failure { called = true }
      expect(called).to be(false)
    end

    it 'returns self for chaining' do
      result = described_class.new(true)
      expect(result.on_success { nil }).to be(result)
      expect(result.on_failure { nil }).to be(result)
    end
  end

  describe '#to_h' do
    it 'converts to hash representation' do
      result = described_class.new(true, data: 'data', errors: ['error'], metadata: { key: 'value' })
      expect(result.to_h).to eq({
                                  success: true,
                                  data: 'data',
                                  errors: ['error'],
                                  metadata: { key: 'value' }
                                })
    end
  end

  describe 'immutability' do
    it 'freezes metadata' do
      metadata = { key: 'value' }
      result = described_class.new(true, metadata: metadata)
      expect(result.metadata).to be_frozen
    end

    it "does not freeze the caller's metadata hash" do
      metadata = { key: 'value' }
      described_class.new(true, metadata: metadata)
      expect(metadata).not_to be_frozen
    end

    it 'uses a distinct empty errors array per instance' do
      a = described_class.new(false)
      b = described_class.new(false)
      expect(a.errors).to eq([])
      expect(a.errors).not_to equal(b.errors)
    end

    it 'freezes errors' do
      result = described_class.new(false, errors: ['x'])
      expect(result.errors).to be_frozen
    end

    it 'dupes caller errors so mutating the original does not affect the result' do
      errs = ['a']
      result = described_class.new(false, errors: errs)
      errs << 'b'
      expect(result.errors).to eq(['a'])
    end

    it 'uses a distinct empty metadata hash per instance' do
      a = described_class.new(true)
      b = described_class.new(true)
      expect(a.metadata).to eq({})
      expect(a.metadata).not_to equal(b.metadata)
    end
  end
end
