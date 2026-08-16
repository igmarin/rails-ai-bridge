# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::ConfidenceTag do
  describe '.tag' do
    it 'marks ActiveRecord reflection as verified' do
      expect(described_class.tag(:reflection)).to eq('[VERIFIED]')
    end

    it 'marks rubydex/Prism as verified' do
      expect(described_class.tag(:rubydex)).to eq('[VERIFIED]')
      expect(described_class.tag(:prism)).to eq('[VERIFIED]')
    end

    it 'marks live schema reflection as verified' do
      expect(described_class.tag(:live)).to eq('[VERIFIED]')
    end

    it 'marks source-regex extracts as inferred' do
      expect(described_class.tag(:regex)).to eq('[INFERRED]')
    end

    it 'marks static schema parses as inferred' do
      expect(described_class.tag(:static)).to eq('[INFERRED]')
    end

    it 'under-claims when the source is unknown' do
      expect(described_class.tag(nil)).to eq('[INFERRED]')
    end

    it 'does not invent a third status' do
      expect(described_class.tag(:regex)).to eq('[INFERRED]')
      expect(described_class.tag(:mystery)).to eq('[INFERRED]')
    end
  end

  describe '.tagged' do
    it 'appends the tag to the fact line' do
      expect(described_class.tagged('has_many :posts', :reflection)).to eq('has_many :posts [VERIFIED]')
    end
  end
end
