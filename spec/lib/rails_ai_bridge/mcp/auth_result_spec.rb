# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Mcp::AuthResult do
  describe '.ok' do
    it 'builds a successful result with no context' do
      result = described_class.ok
      expect(result.success?).to be true
      expect(result.failure?).to be false
      expect(result.context).to be_nil
      expect(result.error).to be_nil
    end

    it 'builds a successful result carrying an arbitrary context' do
      result = described_class.ok({ user_id: 42 })
      expect(result.success?).to be true
      expect(result.context).to eq({ user_id: 42 })
    end
  end

  describe '.fail' do
    it 'builds a failure result with default :unauthorized error' do
      result = described_class.fail
      expect(result.failure?).to be true
      expect(result.success?).to be false
      expect(result.error).to eq(:unauthorized)
      expect(result.context).to be_nil
    end

    it 'accepts a custom error symbol' do
      result = described_class.fail(:missing_token)
      expect(result.error).to eq(:missing_token)
    end
  end
end
