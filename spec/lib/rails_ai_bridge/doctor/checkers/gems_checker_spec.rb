# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Doctor::Checkers::GemsChecker do
  let(:app) { Rails.application }
  let(:checker) { described_class.new(app) }

  describe '#call' do
    let(:lock_path) { File.join(app.root, 'Gemfile.lock') }

    context 'when Gemfile.lock exists' do
      before { allow(File).to receive(:exist?).with(lock_path).and_return(true) }

      it 'returns a pass check' do
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to eq('Gemfile.lock found')
      end
    end

    context 'when Gemfile.lock does not exist' do
      before { allow(File).to receive(:exist?).with(lock_path).and_return(false) }

      it 'returns a warn check' do
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to eq('Gemfile.lock not found')
        expect(result.fix).to include('bundle install')
      end
    end
  end
end
