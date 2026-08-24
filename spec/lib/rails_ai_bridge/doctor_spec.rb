# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Doctor do
  let(:doctor) { described_class.new(Rails.application) }

  describe '#run' do
    subject(:result) { doctor.run }

    it 'returns checks and a score' do
      expect(result).to have_key(:checks)
      expect(result).to have_key(:score)
    end

    it 'returns an array of checks' do
      expect(result[:checks]).to all(be_a(RailsAiBridge::Doctor::Check))
    end

    it 'computes a score between 0 and 100' do
      expect(result[:score]).to be_between(0, 100)
    end

    it 'checks schema presence' do
      names = result[:checks].map(&:name)
      expect(names).to include('Schema')
    end

    it 'includes new v0.4.0 checks' do
      names = result[:checks].map(&:name)
      expect(names).to include('Controllers', 'Views', 'I18n', 'Tests')
    end

    it 'includes context quality checks for UI stacks and bridge metadata' do
      names = result[:checks].map(&:name)
      expect(names).to include('View MCP tool', 'Stimulus MCP tool', 'Bridge metadata')
    end

    it 'runs 17 total checks' do
      expect(result[:checks].size).to eq(17)
    end

    it 'checks MCP server buildability' do
      mcp_check = result[:checks].find { |c| c.name == 'MCP server' }
      expect(mcp_check.status).to eq(:pass)
    end

    it 'warns when views exist but the views introspector is disabled' do
      saved = RailsAiBridge.configuration.introspectors.dup
      RailsAiBridge.configuration.introspectors -= [:views]

      current = doctor.run
      check = current[:checks].find { |c| c.name == 'View MCP tool' }

      expect(check.status).to eq(:warn)
      expect(check.message).to include(':views')
    ensure
      RailsAiBridge.configuration.introspectors = saved
    end

    it 'all checks have a name and message' do
      result[:checks].each do |check|
        expect(check.name).to be_a(String)
        expect(check.message).to be_a(String)
        expect(check.status).to be_in(%i[pass warn fail])
      end
    end

    it 'counts :fail checks as 0 in the readiness score' do
      fail_check = RailsAiBridge::Doctor::Check.new(name: 'Fail', status: :fail, message: 'failed', fix: nil)
      pass_check = RailsAiBridge::Doctor::Check.new(name: 'Pass', status: :pass, message: 'ok', fix: nil)
      allow(RailsAiBridge::Doctor::Checkers::SchemaChecker).to receive(:new).and_return(
        instance_double(RailsAiBridge::Doctor::Checkers::SchemaChecker, call: fail_check)
      )
      allow(RailsAiBridge::Doctor::Checkers::ModelsChecker).to receive(:new).and_return(
        instance_double(RailsAiBridge::Doctor::Checkers::ModelsChecker, call: pass_check)
      )

      score = doctor.run[:score]

      # 1 fail (0) + 1 pass (10) + 15 others (all pass = 150) = 160 / 170 = 94
      expect(score).to be < 100
    end
  end
end
