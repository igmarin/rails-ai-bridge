# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Doctor::Checkers::ViewMcpToolChecker do
  let(:app) { Rails.application }
  let(:checker) { described_class.new(app) }

  describe '#call' do
    before do
      allow(checker).to receive(:view_files_present?).and_return(true)
      allow(RailsAiBridge.configuration.introspectors).to receive(:include?).with(:views).and_return(true)
    end

    context 'when view tool is registered' do
      it 'returns a pass check' do
        allow(checker).to receive(:tool_registered?).with('rails_get_view').and_return(true)
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to include('available for view inspection')
      end
    end

    context 'when view tool is not registered' do
      it 'returns a fail check' do
        allow(checker).to receive(:tool_registered?).with('rails_get_view').and_return(false)
        result = checker.call
        expect(result.status).to eq(:fail)
        expect(result.message).to include('is not registered')
      end
    end

    context 'when view files are not present' do
      it 'returns a pass check and skips further checks' do
        allow(checker).to receive(:view_files_present?).and_return(false)
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to include('view MCP tool not required')
      end
    end

    context 'when views introspector is disabled' do
      it 'returns a warn check' do
        allow(RailsAiBridge.configuration.introspectors).to receive(:include?).with(:views).and_return(false)
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to include('introspector is disabled')
      end
    end
  end
end
