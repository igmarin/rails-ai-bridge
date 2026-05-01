# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ConventionDetector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'returns architecture as an array' do
      expect(result[:architecture]).to be_an(Array)
    end

    it 'returns patterns as an array' do
      expect(result[:patterns]).to be_an(Array)
    end

    it 'returns directory_structure as a hash' do
      expect(result[:directory_structure]).to be_a(Hash)
    end

    it 'detects models directory' do
      expect(result[:directory_structure]).to have_key('app/models')
    end

    it 'returns config_files as an array' do
      expect(result[:config_files]).to be_an(Array)
    end

    it 'does not advertise Rails credentials or key files as config files' do
      allow(introspector).to receive(:file_exists?).and_return(true)

      expect(result[:config_files]).not_to include('config/credentials.yml.enc')
      expect(result[:config_files]).not_to include('config/master.key')
    end
  end
end
