# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::SearchCode do
  describe '.call' do
    around do |example|
      saved_types = RailsAiBridge.configuration.search_code_allowed_file_types.dup
      saved_max = RailsAiBridge.configuration.search_code_pattern_max_bytes
      saved_timeout = RailsAiBridge.configuration.search_code_timeout_seconds
      example.run
    ensure
      RailsAiBridge.configuration.search_code_allowed_file_types = saved_types
      RailsAiBridge.configuration.search_code_pattern_max_bytes = saved_max
      RailsAiBridge.configuration.search_code_timeout_seconds = saved_timeout
    end

    it 'rejects invalid file_type with special characters' do
      result = described_class.call(pattern: 'test', file_type: 'rb;rm -rf /')
      text = result.content.first[:text]
      expect(text).to include('Invalid file_type')
    end

    it 'rejects file_type not on the allowlist (e.g. secrets-friendly extensions)' do
      %w[key pem env p12].each do |ext|
        result = described_class.call(pattern: 'test', file_type: ext)
        text = result.content.first[:text]
        expect(text).to include('Invalid file_type'), "expected #{ext} to be rejected"
      end
    end

    it 'rejects alphanumeric file_type that is not allowed (e.g. txt)' do
      result = described_class.call(pattern: 'test', file_type: 'txt')
      text = result.content.first[:text]
      expect(text).to include('Invalid file_type')
    end

    it 'accepts allowlisted file_type' do
      result = described_class.call(pattern: 'class', file_type: 'rb')
      text = result.content.first[:text]
      expect(text).not_to include('Invalid file_type')
    end

    it 'accepts file_type added via config.search_code_allowed_file_types' do
      RailsAiBridge.configuration.search_code_allowed_file_types = %w[md]
      result = described_class.call(pattern: 'heading', file_type: 'md')
      text = result.content.first[:text]
      expect(text).not_to include('Invalid file_type')
    end

    it 'caps max_results at 100' do
      result = described_class.call(pattern: 'class', max_results: 500)
      # Should not error — just verify it runs
      expect(result).to be_a(MCP::Tool::Response)
    end

    it 'prevents path traversal' do
      result = described_class.call(pattern: 'test', path: '../../etc')
      text = result.content.first[:text]
      expect(text).to match(/Path not (found|allowed)/)
    end

    it 'returns not found for a subdirectory that does not exist under Rails.root' do
      result = described_class.call(pattern: 'class', path: 'no_such_directory_rails_ai_bridge')
      text = result.content.first[:text]
      expect(text).to include('Path not found')
    end

    it 'returns results for a valid search' do
      # This test now indirectly verifies the Formatter is used.
      result = described_class.call(pattern: 'ActiveRecord::Schema', file_type: 'rb')
      text = result.content.first[:text]
      expect(text).to include('# Search: `ActiveRecord::Schema`')
      expect(text).to include('results') # Checks for the results count
      expect(text).to include('```') # Checks for markdown code block
      expect(text).to include('db/schema.rb:1: ActiveRecord::Schema.define(version:') # Checks for actual content
    end

    it 'returns a not-found message for unmatched patterns' do
      result = described_class.call(pattern: 'zzz_impossible_pattern_zzz_42')
      text = result.content.first[:text]
      expect(text).to include('No results found')
    end

    it 'returns a friendly error for invalid regex in Ruby fallback mode' do
      allow(described_class).to receive(:ripgrep_available?).and_return(false)

      result = described_class.call(pattern: '(')
      text = result.content.first[:text]

      expect(text).to include('Invalid pattern')
    end

    it 'rejects patterns larger than search_code_pattern_max_bytes' do
      RailsAiBridge.configuration.search_code_pattern_max_bytes = 8
      result = described_class.call(pattern: 'ninechars')
      text = result.content.first[:text]
      expect(text).to include('Pattern exceeds maximum length')
    end

    it 'surfaces a timeout when Timeout.timeout fires during search' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      allow(described_class).to receive(:ripgrep_available?).and_return(true)

      result = described_class.call(pattern: 'class')
      text = result.content.first[:text]
      expect(text).to include('Search timed out')
    end

    it 'memoizes a missing ripgrep executable' do
      described_class.remove_instance_variable(:@ripgrep_available) if described_class.instance_variable_defined?(:@ripgrep_available)
      allow(described_class).to receive(:system).and_return(false)

      2.times { described_class.send(:ripgrep_available?) }

      expect(described_class).to have_received(:system).once
    ensure
      described_class.remove_instance_variable(:@ripgrep_available) if described_class.instance_variable_defined?(:@ripgrep_available)
    end
  end
end
