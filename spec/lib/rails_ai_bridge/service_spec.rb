# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Service do
  describe '.call' do
    it 'executes the service instance and returns result' do
      service_class = Class.new(described_class) do
        def call
          'test_result'
        end
      end

      result = service_class.call
      expect(result).to eq('test_result')
    end

    it 'passes arguments to initialize and call' do
      service_class = Class.new(described_class) do
        def initialize(first_arg, keyword_arg: nil)
          super()
          @first_arg = first_arg
          @keyword_arg = keyword_arg
        end

        def call
          { first_arg: @first_arg, keyword_arg: @keyword_arg }
        end
      end

      result = service_class.call('test_arg', keyword_arg: 'test_kwarg')
      expect(result).to eq({ first_arg: 'test_arg', keyword_arg: 'test_kwarg' })
    end
  end

  describe '#call' do
    it 'raises NotImplementedError when not overridden' do
      service = described_class.new
      expect { service.call }.to raise_error(NotImplementedError, 'RailsAiBridge::Service must implement #call')
    end
  end

  describe 'inheritance' do
    it 'allows inheritance for specific services' do
      custom_service = Class.new(described_class) do
        def call
          'custom_result'
        end
      end

      result = custom_service.call
      expect(result).to eq('custom_result')
    end
  end
end
