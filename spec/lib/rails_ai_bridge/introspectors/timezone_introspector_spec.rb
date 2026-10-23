# frozen_string_literal: true

require 'spec_helper'

module RailsAiBridge
  module Introspectors
    RSpec.describe TimezoneIntrospector do
      let(:app) { instance_double('Rails::Application', config: config_double) }
      let(:config_double) { instance_double('Rails::Application::Configuration') }

      subject { described_class.new(app).call }

      describe '#call' do
        context 'when the app is booted and time_zone is set' do
          before do
            allow(app).to receive(:config).and_return(config_double)
            allow(config_double).to receive(:time_zone).and_return('UTC')
            allow(Time).to receive(:zone).and_return('UTC')
          end

          it 'returns the timezone name' do
            expect(subject[:time_zone]).to eq('UTC')
          end

          it 'sets the timezone source to rails_config when equal to config' do
            expect(subject[:time_zone_source]).to eq(:rails_config)
          end

          it 'sets timezone_confirmed to true when Time.zone matches config' do
            expect(subject[:time_zone_confirmed]).to be(true)
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
            allow(app).to receive(:config).and_return(config_double)
            allow(config_double).to receive(:time_zone).and_return('Mars/UTC')
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
            allow(app).to receive(:config).and_return(config_double)
            allow(config_double).to receive(:time_zone).and_return('Eastern Time (US & Canada)')
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
