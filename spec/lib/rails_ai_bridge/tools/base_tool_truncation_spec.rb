# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::BaseTool do
  describe '.text_response truncation' do
    around do |example|
      original_max = RailsAiBridge.configuration.max_tool_response_chars
      RailsAiBridge.configuration.max_tool_response_chars = 100
      example.run
    ensure
      RailsAiBridge.configuration.max_tool_response_chars = original_max
    end

    it 'truncates responses exceeding max chars' do
      long_text = 'x' * 200
      result = described_class.text_response(long_text)
      text = result.content.first[:text]
      expect(text).to include('Response truncated')
      expect(text).to include('200 chars')
    end

    it 'does not truncate short responses' do
      short_text = 'hello'
      result = described_class.text_response(short_text)
      text = result.content.first[:text]
      expect(text).to eq('hello')
    end

    it 'includes hint to use detail:summary' do
      long_text = 'x' * 200
      result = described_class.text_response(long_text)
      text = result.content.first[:text]
      expect(text).to include('detail:"summary"')
    end

    it 'keeps the final response within the configured limit' do
      long_text = 'x' * 200
      result = described_class.text_response(long_text)
      text = result.content.first[:text]

      expect(text.length).to be <= 100
    end
  end
end
