# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'confidence tags on schema and model tools' do
  describe RailsAiBridge::Tools::GetModelDetails do
    let(:content) { described_class.call(**params).content.first[:text] }

    before do
      allow(described_class).to receive(:cached_section) do |sym|
        case sym
        when :models then models_data
        when :non_ar_models then { non_ar_models: [] }
        end
      end
    end

    context 'when a model has a reflected association' do
      let(:models_data) do
        {
          'User' => {
            table_name: 'users',
            associations: [{ name: 'posts', type: 'has_many', source: :reflection }]
          }
        }
      end
      let(:params) { { model: 'User' } }

      it 'tags the association as [VERIFIED] in markdown' do
        expect(content).to include('`has_many` **posts**')
        expect(content).to match(/`has_many` \*\*posts\*\*.*\[VERIFIED\]/)
      end
    end

    context 'when a model has a regex-only source macro' do
      let(:models_data) do
        {
          'User' => {
            table_name: 'users',
            associations: [],
            has_secure_password: true
          }
        }
      end
      let(:params) { { model: 'User' } }

      it 'tags the macro as [INFERRED] in markdown' do
        expect(content).to include('has_secure_password')
        expect(content).to match(/has_secure_password.*\[INFERRED\]/)
      end

      it 'does not tag the regex-only macro as [VERIFIED]' do
        macro_line = content.lines.find { |line| line.include?('has_secure_password') }
        expect(macro_line).not_to include('[VERIFIED]')
      end
    end

    context 'when associations are missing' do
      let(:models_data) do
        { 'User' => { table_name: 'users' } }
      end
      let(:params) { { model: 'User' } }

      it 'omits the associations section instead of claiming verified empty' do
        expect(content).not_to include('## Associations')
        expect(content).not_to include('0 associations [VERIFIED]')
      end
    end

    context 'with detail: full listing' do
      let(:models_data) do
        {
          'User' => {
            table_name: 'users',
            associations: [{ name: 'posts', type: 'has_many', source: :reflection }]
          }
        }
      end
      let(:params) { { detail: 'full' } }

      it 'tags reflected associations as [VERIFIED]' do
        expect(content).to include('has_many :posts [VERIFIED]')
      end
    end
  end

  describe RailsAiBridge::Tools::GetSchema do
    let(:content) { described_class.call(**params).content.first[:text] }
    let(:tables) do
      {
        'users' => {
          columns: [{ name: 'id', type: 'integer', null: false, default: nil }],
          indexes: [],
          foreign_keys: []
        }
      }
    end

    before do
      allow(described_class).to receive(:cached_section).with(:schema).and_return(schema_data)
    end

    context 'when schema comes from a live ActiveRecord connection' do
      let(:schema_data) { { adapter: 'SQLite', source: :live, tables: tables, total_tables: 1 } }

      %w[summary standard full].each do |detail|
        context "with detail: #{detail}" do
          let(:params) { { detail: detail } }

          it 'tags tables as [VERIFIED]' do
            expect(content).to include('[VERIFIED]')
            expect(content).not_to include('[INFERRED]')
          end
        end
      end

      context 'when requesting a single table' do
        let(:params) { { table: 'users' } }

        it 'tags the table as [VERIFIED]' do
          expect(content).to include('## Table: users [VERIFIED]')
        end
      end
    end

    context 'when schema is a static regex parse' do
      let(:schema_data) do
        { adapter: 'static_parse', source: :static, tables: tables, total_tables: 1,
          note: 'Parsed from db/schema.rb (no DB connection)' }
      end

      %w[summary standard full].each do |detail|
        context "with detail: #{detail}" do
          let(:params) { { detail: detail } }

          it 'tags tables as [INFERRED]' do
            expect(content).to include('[INFERRED]')
            expect(content).not_to include('[VERIFIED]')
          end
        end
      end

      context 'when requesting a single table' do
        let(:params) { { table: 'users' } }

        it 'tags the table as [INFERRED]' do
          expect(content).to include('## Table: users [INFERRED]')
        end
      end
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::SingleModelFormatter do
    it 'tags a reflected association as [VERIFIED]' do
      output = described_class.new(
        name: 'User',
        data: { associations: [{ type: 'has_many', name: 'posts', source: :reflection }] }
      ).call

      expect(output).to match(/`has_many` \*\*posts\*\*.*\[VERIFIED\]/)
    end

    it 'tags a regex-only macro as [INFERRED] and never as [VERIFIED]' do
      output = described_class.new(
        name: 'User',
        data: { has_secure_password: true }
      ).call

      expect(output).to match(/has_secure_password.*\[INFERRED\]/)
      expect(output).not_to match(/has_secure_password.*\[VERIFIED\]/)
    end
  end
end
