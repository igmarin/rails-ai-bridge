# frozen_string_literal: true

require 'spec_helper'

# Guard spec that prevents documentation counts from drifting away from the
# actual constants defined in the codebase. When a tool or introspector is
# added or removed, the corresponding docs must be updated in the same change;
# this spec fails with a clear message until they do.
RSpec.describe 'documentation parity with source constants' do
  let(:readme_path) { File.expand_path('../../../README.md', __dir__) }
  let(:readme_content) { File.read(readme_path) }
  let(:server_json) { JSON.parse(File.read(File.expand_path('../../../server.json', __dir__))) }
  let(:contributing_content) { File.read(File.expand_path('../../../CONTRIBUTING.md', __dir__)) }

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

  describe 'server.json tool count' do
    it 'matches the number of tools in Server::TOOLS' do
      actual_count = RailsAiBridge::Server::TOOLS.size
      match = server_json['description'].match(/(\d+)\s+read-only\s+tools/)

      expect(match).not_to be_nil,
                           'server.json description must state the tool count as "N read-only tools"'

      documented_count = match[1].to_i
      expect(documented_count).to eq(actual_count),
                                  "server.json says #{documented_count} tools but " \
                                  "RailsAiBridge::Server::TOOLS has #{actual_count}. " \
                                  'Update server.json to match.'
    end
  end

  describe 'CONTRIBUTING.md tool count' do
    it 'matches the number of tools in Server::TOOLS' do
      actual_count = RailsAiBridge::Server::TOOLS.size
      counts = contributing_content.scan(/(\d+)\s+built-in MCP tools/).flatten.map(&:to_i)

      expect(counts).not_to be_empty,
                            'CONTRIBUTING.md must state the tool count as "N built-in MCP tools"'

      expect(counts).to all(eq(actual_count)),
                        "CONTRIBUTING.md mentions tool counts #{counts.inspect} but " \
                        "RailsAiBridge::Server::TOOLS has #{actual_count}. " \
                        'Update CONTRIBUTING.md to match.'
    end
  end

  describe ':full preset introspector count' do
    it 'matches the count documented in AGENTS.md and CLAUDE.md' do
      actual_count = RailsAiBridge::Configuration::PRESETS[:full].size
      expected_count = 27

      expect(actual_count).to eq(expected_count),
                              'RailsAiBridge::Configuration::PRESETS[:full] has ' \
                              "#{actual_count} introspectors, expected #{expected_count}. " \
                              'Update the docs if the preset changed.'
    end
  end

  describe 'AGENTS.md / CLAUDE.md preset and style claims' do
    let(:agents_content) { File.read(File.expand_path('../../../AGENTS.md', __dir__)) }
    let(:claude_content) { File.read(File.expand_path('../../../CLAUDE.md', __dir__)) }

    it 'does not describe non_ar_models as opt-in-only' do
      expect(RailsAiBridge::Configuration::PRESETS[:full]).to include(:non_ar_models),
                                                              ':full no longer includes non_ar_models; ' \
                                                              'update AGENTS.md/CLAUDE.md wording.'

      [agents_content, claude_content].each do |content|
        expect(content).not_to include('`non_ar_models` not listed in those presets'),
                               'AGENTS.md/CLAUDE.md must not claim non_ar_models is excluded from ' \
                               'the presets; it ships in :full.'
        expect(content).not_to include('optional extras such as `database_stats`, `non_ar_models`'),
                               'AGENTS.md/CLAUDE.md must not list non_ar_models as an optional ' \
                               'extra; it ships in :full.'
      end
    end

    it 'does not claim the project follows the rubocop-rails-omakase style' do
      [agents_content, claude_content].each do |content|
        expect(content).not_to match(/rubocop[- ]rails[- ]omakase/),
                               'AGENTS.md/CLAUDE.md must not claim the rubocop-rails-omakase style; ' \
                               '.rubocop.yml uses its own custom limits.'
      end
    end
  end

  describe ':standard preset introspector count' do
    it 'matches the count documented in AGENTS.md and CLAUDE.md' do
      actual_count = RailsAiBridge::Configuration::PRESETS[:standard].size
      expected_count = 9

      expect(actual_count).to eq(expected_count),
                              'RailsAiBridge::Configuration::PRESETS[:standard] has ' \
                              "#{actual_count} introspectors, expected #{expected_count}. " \
                              'Update the docs if the preset changed.'
    end
  end
end
