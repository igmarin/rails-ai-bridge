# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::TimezoneIntrospector do
  subject(:result) { described_class.new(app).call }

  let(:config) { double('config', time_zone: 'UTC') }
  let(:app) { double('app', config: config) }

  describe '#call' do
    context 'when the app is booted and Time.zone matches config.time_zone' do
      before { allow(Time).to receive(:zone).and_return(ActiveSupport::TimeZone['UTC']) }

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

    ['Eastern Time (US & Canada)', 'America/New_York', 'Europe/London'].each do |zone_name|
      context "when #{zone_name} matches the runtime zone" do
        before do
          allow(config).to receive(:time_zone).and_return(zone_name)
          allow(Time).to receive(:zone).and_return(ActiveSupport::TimeZone[zone_name])
        end

        it 'confirms the configured zone using real ActiveSupport objects' do
          expect(result).to eq(time_zone: zone_name, time_zone_confirmed: true)
        end
      end
    end

    context 'when Rails and IANA names identify the same runtime zone' do
      before do
        allow(config).to receive(:time_zone).and_return('Eastern Time (US & Canada)')
        allow(Time).to receive(:zone).and_return(ActiveSupport::TimeZone['America/New_York'])
      end

      it 'confirms the timezone across name formats' do
        expect(result[:time_zone_confirmed]).to be(true)
      end
    end

    context 'when the configured timezone is unknown' do
      before do
        allow(config).to receive(:time_zone).and_return('Unknown/Zone')
        allow(Time).to receive(:zone).and_return(ActiveSupport::TimeZone['UTC'])
      end

      it 'preserves the configured value without confirming it' do
        expect(result).to eq(time_zone: 'Unknown/Zone', time_zone_confirmed: false)
      end
    end

    context 'when Time.zone differs from config.time_zone' do
      before do
        allow(Time).to receive(:zone).and_return(ActiveSupport::TimeZone['UTC'])
        allow(config).to receive(:time_zone).and_return('Eastern Time (US & Canada)')
      end

      it 'returns the configured timezone' do
        expect(result[:time_zone]).to eq('Eastern Time (US & Canada)')
      end

      it 'does not confirm the timezone' do
        expect(result[:time_zone_confirmed]).to be(false)
      end
    end

    context 'when the runtime timezone is unavailable' do
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
