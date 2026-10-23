# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::TimezoneIntrospector do
  subject(:result) { described_class.new(app).call }

  let(:config) { double('config', time_zone: 'UTC') }
  let(:app) { double('app', config: config) }

  describe '#call' do
    context 'when the app is booted and Time.zone matches config.time_zone' do
      before { allow(Time).to receive(:zone).and_return('UTC') }

      it 'returns the configured timezone' do
        expect(result[:time_zone]).to eq('UTC')
      end

      it 'confirms the timezone' do
        expect(result[:time_zone_confirmed]).to be(true)
      end

      it 'does not include an error key' do
        expect(result).not_to have_key(:error)
      end
    end

    context 'when Time.zone differs from config.time_zone' do
      before do
        allow(Time).to receive(:zone).and_return('UTC')
        allow(config).to receive(:time_zone).and_return('Eastern Time (US & Canada)')
      end

      it 'returns the configured timezone' do
        expect(result[:time_zone]).to eq('Eastern Time (US & Canada)')
      end

      it 'does not confirm the timezone' do
        expect(result[:time_zone_confirmed]).to be(false)
      end
    end

    context 'when Rails was never booted (Time.zone is nil)' do
      before { allow(Time).to receive(:zone).and_return(nil) }

      it 'still returns the configured timezone' do
        expect(result[:time_zone]).to eq('UTC')
      end

      it 'marks the timezone as unconfirmed' do
        expect(result[:time_zone_confirmed]).to be(false)
      end
    end

    context 'when config.time_zone raises' do
      before do
        allow(config).to receive(:time_zone).and_raise(StandardError, 'tz boom')
      end

      it 'returns an error hash' do
        expect(result).to eq(error: 'tz boom')
      end

      it 'never raises' do
        expect { result }.not_to raise_error
      end
    end
  end
end
