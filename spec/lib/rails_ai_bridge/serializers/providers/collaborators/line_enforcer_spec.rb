# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::Collaborators::LineEnforcer do
  subject(:enforcer) { described_class.new(config) }

  let(:config) { RailsAiBridge::Configuration.new }
  let(:lines) { Array.new(10) { |i| "line #{i}" } }

  describe '#enforce' do
    it 'returns original lines when within limit' do
      allow(config).to receive(:claude_max_lines).and_return(20)

      expect(enforcer.enforce(lines)).to eq(lines)
    end

    it 'trims to the budget and appends the MCP pointer' do
      allow(config).to receive(:claude_max_lines).and_return(5)

      result = enforcer.enforce(lines)

      expect(result).to eq(['line 0', 'line 1', 'line 2', '', described_class::TRIMMER_NOTICE])
      expect(result.size).to eq(5)
    end

    it 'returns only the notice when the budget is one' do
      allow(config).to receive(:claude_max_lines).and_return(1)

      expect(enforcer.enforce(lines)).to eq([described_class::TRIMMER_NOTICE])
    end

    it 'returns an empty document when the budget is zero' do
      allow(config).to receive(:claude_max_lines).and_return(0)

      expect(enforcer.enforce(lines)).to eq([])
    end

    it 'treats a nil limit as zero' do
      allow(config).to receive(:claude_max_lines).and_return(nil)

      expect(enforcer.enforce(lines)).to eq([])
    end

    it 'returns empty lines untouched within a zero budget' do
      allow(config).to receive(:claude_max_lines).and_return(0)

      expect(enforcer.enforce([])).to eq([])
    end
  end
end
