# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::GetSchema do
  let(:schema_data) do
    {
      total_tables: 2,
      tables: {
        'users' => { columns: [{ name: 'id', type: 'integer' }], indexes: [], foreign_keys: [] },
        'posts' => { columns: [{ name: 'id', type: 'integer' }, { name: 'title', type: 'string' }], indexes: [],
                     foreign_keys: [] }
      }
    }
  end
  let(:response) { described_class.call(**params) }
  let(:content) { response.content.first[:text] }

  before do
    allow(described_class).to receive(:cached_section).with(:schema).and_return(schema_data)
  end

  describe '.call' do
    context 'when requesting a specific table' do
      let(:params) { { table: 'users' } }

      it 'returns the detail for that table' do
        expect(content).to include('## Table: users')
        expect(content).to include('| id | integer |')
      end
    end

    context "with detail: 'summary'" do
      let(:params) { { detail: 'summary' } }

      it 'delegates to the SummaryFormatter' do
        expect(content).to include('# Schema Summary (2 tables)')
        expect(content).to include('- **users** — 1 columns, 0 indexes')
        expect(content).to include('- **posts** — 2 columns, 0 indexes')
      end
    end

    context "with detail: 'standard'" do
      let(:params) { { detail: 'standard' } }

      it 'delegates to the StandardFormatter' do
        expect(content).to include('# Schema (2 tables, showing 2)')
        expect(content).to include('### users')
        expect(content).to include('id:integer')
        expect(content).to include('### posts')
      end
    end

    context "with detail: 'full'" do
      let(:params) { { detail: 'full' } }

      it 'delegates to the FullFormatter' do
        expect(content).to include('# Schema Full Detail (2 of 2 tables)')
        expect(content).to include('## Table: users')
        expect(content).to include('## Table: posts')
      end
    end

    context 'when schema is not available' do
      let(:schema_data) { nil }
      let(:params) { {} }

      it 'returns a helpful message' do
        expect(content).to include('Schema introspection not available')
      end
    end
  end
end
