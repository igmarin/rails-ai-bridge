# frozen_string_literal: true

require 'spec_helper'

# Guard spec that prevents documentation counts from drifting away from the
# actual constants defined in the codebase. When a tool or introspector is
# added or removed, the corresponding docs must be updated in the same change;
# this spec fails with a clear message until they do.
RSpec.describe 'documentation parity with source constants' do
  let(:readme_path) { File.expand_path('../../../README.md', __dir__) }
  let(:readme_content) { File.read(readme_path) }

  describe 'MCP tool count' do
    it 'matches the number of tools in README.md' do
      actual_count = RailsAiBridge::Server::TOOLS.size
      # The README comparison table lists the tool count as "N read-only".
      match = readme_content.match(/(\d+)\s+read-only\s+`rails_\*`\s+tools/)

      expect(match).not_to be_nil,
                           'README.md must state the tool count as "N read-only `rails_*` tools"'

      documented_count = match[1].to_i
      expect(documented_count).to eq(actual_count),
                                  "README.md says #{documented_count} tools but " \
                                  "RailsAiBridge::Server::TOOLS has #{actual_count}. " \
                                  'Update README.md to match.'
    end
  end

  describe ':full preset introspector count' do
    it 'matches the count documented in AGENTS.md and CLAUDE.md' do
      actual_count = RailsAiBridge::Configuration::PRESETS[:full].size
      expected_count = 27

      expect(actual_count).to eq(expected_count),
                               "RailsAiBridge::Configuration::PRESETS[:full] has " \
                               "#{actual_count} introspectors, expected #{expected_count}. " \
                               'Update the docs if the preset changed.'
    end
  end

  describe ':standard preset introspector count' do
    it 'matches the count documented in AGENTS.md and CLAUDE.md' do
      actual_count = RailsAiBridge::Configuration::PRESETS[:standard].size
      expected_count = 9

      expect(actual_count).to eq(expected_count),
                               "RailsAiBridge::Configuration::PRESETS[:standard] has " \
                               "#{actual_count} introspectors, expected #{expected_count}. " \
                               'Update the docs if the preset changed.'
    end
  end
end
