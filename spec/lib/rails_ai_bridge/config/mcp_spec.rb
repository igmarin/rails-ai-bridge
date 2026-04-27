# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Config::Mcp do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'has sensible defaults' do
      expect(config.mode).to eq(:hybrid)
      expect(config.security_profile).to eq(:balanced)
      expect(config.rate_limit_max_requests).to be_nil
      expect(config.rate_limit_window_seconds).to eq(60)
      expect(config.http_log_json).to be(false)
      expect(config.authorize).to be_nil
      expect(config.require_auth_in_production).to be(false)
      expect(config.require_http_auth).to be(false)
    end
  end

  describe '#effective_http_rate_limit_max_requests' do
    it 'returns the explicit value when a positive integer is set' do
      config.rate_limit_max_requests = 100
      expect(config.effective_http_rate_limit_max_requests).to eq(100)
    end

    it 'returns 0 when explicitly set to 0 (disabled)' do
      config.rate_limit_max_requests = 0
      expect(config.effective_http_rate_limit_max_requests).to eq(0)
    end

    it 'returns 0 when set to a negative integer' do
      config.rate_limit_max_requests = -5
      expect(config.effective_http_rate_limit_max_requests).to eq(0)
    end

    it 'coerces a numeric string to integer' do
      config.rate_limit_max_requests = '200'
      expect(config.effective_http_rate_limit_max_requests).to eq(200)
    end

    it 'returns 0 for a zero string' do
      config.rate_limit_max_requests = '0'
      expect(config.effective_http_rate_limit_max_requests).to eq(0)
    end

    context 'when rate_limit_max_requests is nil (implicit mode)' do
      before { config.rate_limit_max_requests = nil }

      it 'returns 0 in :dev mode (suppressed)' do
        config.mode = :dev
        expect(config.effective_http_rate_limit_max_requests).to eq(0)
      end

      it 'returns 0 in :hybrid mode when not in production' do
        config.mode = :hybrid
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        expect(config.effective_http_rate_limit_max_requests).to eq(0)
      end

      it 'returns the security profile default in :hybrid mode when in production' do
        config.mode = :hybrid
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        expect(config.effective_http_rate_limit_max_requests).to eq(300) # balanced default
      end

      it 'returns the security profile default in :production mode' do
        config.mode = :production
        expect(config.effective_http_rate_limit_max_requests).to eq(300)
      end

      it 'returns 60 for :strict security profile' do
        config.mode = :production
        config.security_profile = :strict
        expect(config.effective_http_rate_limit_max_requests).to eq(60)
      end

      it 'returns 300 for :balanced security profile' do
        config.mode = :production
        config.security_profile = :balanced
        expect(config.effective_http_rate_limit_max_requests).to eq(300)
      end

      it 'returns 1200 for :relaxed security profile' do
        config.mode = :production
        config.security_profile = :relaxed
        expect(config.effective_http_rate_limit_max_requests).to eq(1_200)
      end

      it 'defaults to 300 for an unknown security profile' do
        config.mode = :production
        config.security_profile = :unknown
        expect(config.effective_http_rate_limit_max_requests).to eq(300)
      end
    end
  end

  describe '#effective_http_rate_limit_window_seconds' do
    it 'returns the configured value when positive' do
      config.rate_limit_window_seconds = 120
      expect(config.effective_http_rate_limit_window_seconds).to eq(120)
    end

    it 'normalizes 0 to 60' do
      config.rate_limit_window_seconds = 0
      expect(config.effective_http_rate_limit_window_seconds).to eq(60)
    end

    it 'normalizes negative values to 60' do
      config.rate_limit_window_seconds = -10
      expect(config.effective_http_rate_limit_window_seconds).to eq(60)
    end
  end

  describe '#http_rate_limit_implicitly_suppressed?' do
    it 'returns true in :dev mode' do
      config.mode = :dev
      expect(config.http_rate_limit_implicitly_suppressed?).to be true
    end

    it 'returns true in :hybrid mode when not in production' do
      config.mode = :hybrid
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      expect(config.http_rate_limit_implicitly_suppressed?).to be true
    end

    it 'returns false in :hybrid mode when in production' do
      config.mode = :hybrid
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      expect(config.http_rate_limit_implicitly_suppressed?).to be false
    end

    it 'returns false in :production mode' do
      config.mode = :production
      expect(config.http_rate_limit_implicitly_suppressed?).to be false
    end

    it 'returns false for an unknown mode' do
      config.mode = :unknown
      expect(config.http_rate_limit_implicitly_suppressed?).to be false
    end

    it 'defaults to :hybrid when mode is nil' do
      config.mode = nil
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      expect(config.http_rate_limit_implicitly_suppressed?).to be true
    end
  end

  # --------------------------------------------------------------------------
  # Characterization tests for Fix #4: rate_limit_max_requests validation
  # --------------------------------------------------------------------------

  describe 'Fix #4: rate_limit_max_requests setter validation' do
    it 'accepts a positive integer' do
      config.rate_limit_max_requests = 100
      expect(config.rate_limit_max_requests).to eq(100)
    end

    it 'accepts nil' do
      config.rate_limit_max_requests = nil
      expect(config.rate_limit_max_requests).to be_nil
    end

    it 'accepts a numeric string (for ENV var usage)' do
      config.rate_limit_max_requests = '200'
      expect(config.rate_limit_max_requests).to eq('200')
    end

    it 'rejects non-numeric strings with ArgumentError' do
      expect { config.rate_limit_max_requests = 'not-a-number' }
        .to raise_error(ArgumentError, /must be Integer, numeric String, or nil/)
    end

    it 'rejects arbitrary objects with ArgumentError' do
      expect { config.rate_limit_max_requests = [1, 2, 3] }
        .to raise_error(ArgumentError, /must be Integer, numeric String, or nil/)
    end

    it 'rejects a float with ArgumentError' do
      expect { config.rate_limit_max_requests = 3.14 }
        .to raise_error(ArgumentError, /must be Integer, numeric String, or nil/)
    end

    it 'accepts zero (disables rate limiting)' do
      config.rate_limit_max_requests = 0
      expect(config.rate_limit_max_requests).to eq(0)
    end

    it 'accepts a negative integer (disables rate limiting)' do
      config.rate_limit_max_requests = -1
      expect(config.rate_limit_max_requests).to eq(-1)
    end
  end
end
