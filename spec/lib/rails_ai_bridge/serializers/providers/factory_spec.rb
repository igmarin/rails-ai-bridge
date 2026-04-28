# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::Factory do
  let(:context) { RailsAiBridge.introspect }

  describe '.for' do
    RailsAiBridge::Serializers::ContextFileSerializer::FORMAT_MAP.each_key do |fmt|
      it "returns an object that responds to #call for :#{fmt}" do
        obj = described_class.for(fmt, context)
        expect(obj).to respond_to(:call)
      end
    end

    it 'returns a NullStrategy for unknown formats' do
      obj = described_class.for(:unknown_fmt, context)
      expect(obj).to be_a(described_class::NullStrategy)
    end
  end

  describe '.split_rules_for' do
    %i[claude codex cursor windsurf copilot].each do |fmt|
      it "returns an object that responds to #call for :#{fmt}" do
        obj = described_class.split_rules_for(fmt, context)
        expect(obj).to respond_to(:call)
      end
    end

    it 'returns a NullSplitRulesStrategy for :gemini (no split rules)' do
      obj = described_class.split_rules_for(:gemini, context)
      expect(obj).to be_a(described_class::NullSplitRulesStrategy)
    end

    it 'NullSplitRulesStrategy#call returns empty written/skipped arrays' do
      obj = described_class.split_rules_for(:json, context)
      Dir.mktmpdir { |dir| expect(obj.call(dir)).to eq({ written: [], skipped: [] }) }
    end
  end
end
