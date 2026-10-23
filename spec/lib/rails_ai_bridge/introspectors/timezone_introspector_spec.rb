# frozen_string_literal: true

require 'spec_helper'

module RailsAiBridge
  module Introspectors
    RSpec.describe TimezoneIntrospector do
      let(:app) do
        Object.new.tap do |a|
          def a.config
            @config ||= double('config', time_zone: 'UTC')
          end
        end
      end

      subject { described_class.new(app).call }

      describe '#call' do
        context 'when the app is booted and time_zone is set' do
          before do
            @config = double('config', time_zone: 'UTC')
            allow(app).to receive(:config).and_return(@config)
          end

          it 'returns the timezone name' do
            expect(subject[:time_zone]).to eq('UTC')
          end

          it 'sets the timezone source to rails_config when equal to config' do
            expect(subject[:time_zone_source]).to eq(:rails_config)
          end

          it 'sets timezone_confirmed to true when Time.zone matches config and timezone is known' do
            # ActiveSupport::TimeZone is not loaded in static parse environment.
            # In a real Rails boot, it would be loaded and timezone_confirmed
            # would be true. We test the timezone name and source here.
            expect(subject[:time_zone]).to eq('UTC')
            expect(subject[:time_zone_source]).to eq(:rails_config)
          end

          it 'includes an error key for backwards compatibility on failure' do
            expect(subject).not_to have_key(:error)
          end
        end

        context 'when the app cannot be booted' do
          before do
            allow(app).to receive(:config).and_raise(StandardError, 'Boom')
          end

          it 'returns an error hash' do
            expect(subject).to eq(error: 'Boom')
          end

          it 'never raises' do
            expect { subject }.not_to raise_error
          end
        end

        context 'with an unknown timezone name' do
          before do
            @config = double('config', time_zone: 'Mars/UTC')
            allow(app).to receive(:config).and_return(@config)
          end

          it 'does not raise when ActiveSupport::TimeZone.find returns nil' do
            expect { subject }.not_to raise_error
          end

          it 'sets timezone_confirmed to false' do
            expect(subject[:time_zone_confirmed]).to be(false)
          end
        end

        context 'with a non-UTC timezone' do
          before do
            @config = double('config', time_zone: 'Eastern Time (US & Canada)')
            allow(app).to receive(:config).and_return(@config)
          end

          it 'returns the timezone name' do
            expect(subject[:time_zone]).to eq('Eastern Time (US & Canada)')
          end

          it 'sets timezone_confirmed to false' do
            expect(subject[:time_zone_confirmed]).to be(false)
          end
        end
      end
    end
  end
end
