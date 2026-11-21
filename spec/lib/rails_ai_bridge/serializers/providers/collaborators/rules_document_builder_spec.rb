# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::Collaborators::RulesDocumentBuilder do
  subject(:builder) { described_class.new(context: context, config: config) }

  let(:config) { RailsAiBridge::Configuration.new }
  let(:context) do
    {
      app_name: 'Acme',
      rails_version: '8.1.4',
      ruby_version: '4.0.10',
      app_overview: { purpose: 'Demo' },
      gems: { 'rspec' => { version: '3.13' } },
      conventions: { architecture: ['service objects'] },
      tests: { framework: 'rspec' },
      config: { cache_store: 'memory_store' },
      models: { 'User' => { associations: [] } }
    }
  end

  describe '#call' do
    it 'assembles a full document with header and section headings' do
      lines = builder.call

      expect(lines).to include('# Acme — Project Rules')
      expect(lines).to include('Rails 8.1.4 | Ruby 4.0.10')
      expect(lines).to include('## Application Stack & Overview')
      expect(lines).to include('## Architecture & Conventions')
      expect(lines).to include('## Key Development Considerations')
      expect(lines).to include('## Models (1 total)')
    end

    it 'renders every line as a string' do
      expect(builder.call).to all(be_a(String))
    end

    it 'keeps the trimmed-models pointer when the model list limit is zero' do
      allow(config).to receive(:copilot_compact_model_list_limit).and_return(0)
      lines = described_class.new(context: context, config: config).call

      expect(lines).to include('- _Use `rails_get_model_details(detail:"summary")` for names._')
    end
  end
end
