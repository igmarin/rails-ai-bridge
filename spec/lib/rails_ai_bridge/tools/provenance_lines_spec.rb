# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::ProvenanceLines do
  describe 'when confidence tags are enabled' do
    subject(:lines) { described_class.new(true) }

    it 'appends the tag for the fact provenance' do
      expect(lines.tag('- `name`', :regex)).to eq('- `name` [INFERRED]')
    end

    it 'tags verified sources as verified' do
      expect(lines.tag('- `set_user`', :reflection)).to eq('- `set_user` [VERIFIED]')
    end

    it 'counts provenances into a footer line' do
      expect(lines.footer(%i[reflection regex regex])).to eq('Verification: [VERIFIED] reflection (1) · [INFERRED] regex (2)')
    end

    it 'counts a missing provenance as heuristic' do
      expect(lines.footer([nil])).to eq('Verification: [INFERRED] heuristic (1)')
    end

    it 'returns no footer when there are no facts' do
      expect(lines.footer([])).to be_nil
    end
  end

  describe 'when confidence tags are disabled' do
    subject(:lines) { described_class.new(false) }

    it 'returns the text unchanged' do
      expect(lines.tag('- `name`', :regex)).to eq('- `name`')
    end

    it 'returns no footer' do
      expect(lines.footer(%i[reflection regex])).to be_nil
    end
  end
end
