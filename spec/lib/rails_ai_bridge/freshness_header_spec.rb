# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::FreshnessHeader do
  let(:timestamp) { '2026-04-03T14:22:00Z' }
  let(:fingerprint) { 'a1b2c3d4e5f6' }
  let(:content) { "# My Rails App\nSome description here." }

  describe '.embed' do
    it 'prepends the freshness HTML comment to the content' do
      result = described_class.embed(content, timestamp, fingerprint)
      expect(result).to start_with("<!-- Generated at: #{timestamp} | Source fingerprint: #{fingerprint} | rails-ai-bridge: v#{RailsAiBridge::VERSION} -->\n")
      expect(result).to include(content)
    end
  end

  describe 'extraction methods' do
    let(:embedded_content) { described_class.embed(content, timestamp, fingerprint) }

    describe '.extract_fingerprint' do
      it 'extracts the fingerprint from a valid header' do
        expect(described_class.extract_fingerprint(embedded_content)).to eq(fingerprint)
      end

      it 'extracts fingerprint from older headers without gem version' do
        old_header = "<!-- Generated at: 2026-04-03T14:22:00Z | Source fingerprint: a1b2c3d4e5f6 -->\n# Title"
        expect(described_class.extract_fingerprint(old_header)).to eq('a1b2c3d4e5f6')
      end

      it 'returns nil if the header is missing or invalid' do
        expect(described_class.extract_fingerprint(content)).to be_nil
        expect(described_class.extract_fingerprint("<!-- Bad format -->\n# Title")).to be_nil
      end
    end

    describe '.extract_timestamp' do
      it 'extracts the timestamp from a valid header' do
        expect(described_class.extract_timestamp(embedded_content)).to eq(timestamp)
      end

      it 'extracts timestamp from older headers without gem version' do
        old_header = "<!-- Generated at: 2026-04-03T14:22:00Z | Source fingerprint: a1b2c3d4e5f6 -->\n# Title"
        expect(described_class.extract_timestamp(old_header)).to eq('2026-04-03T14:22:00Z')
      end

      it 'returns nil if the header is missing or invalid' do
        expect(described_class.extract_timestamp(content)).to be_nil
      end
    end

    describe '.extract_version' do
      it 'extracts the version from a valid header' do
        expect(described_class.extract_version(embedded_content)).to eq(RailsAiBridge::VERSION)
      end

      it 'returns nil for older headers without gem version' do
        old_header = "<!-- Generated at: 2026-04-03T14:22:00Z | Source fingerprint: a1b2c3d4e5f6 -->\n# Title"
        expect(described_class.extract_version(old_header)).to be_nil
      end
    end
  end
end
