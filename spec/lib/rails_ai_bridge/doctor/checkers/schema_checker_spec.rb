# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Doctor::Checkers::SchemaChecker do
  let(:app) { Rails.application }
  let(:checker) { described_class.new(app) }
  let(:schema_rb_path) { File.join(app.root, 'db/schema.rb') }
  let(:structure_sql_path) { File.join(app.root, 'db/structure.sql') }

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(schema_rb_path).and_return(schema_rb_exists)
    allow(File).to receive(:exist?).with(structure_sql_path).and_return(structure_sql_exists)
  end

  describe '#call' do
    context 'when db/schema.rb exists' do
      let(:schema_rb_exists) { true }
      let(:structure_sql_exists) { false }

      it 'returns a pass check naming schema.rb' do
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to eq('db/schema.rb found')
      end
    end

    context 'when only db/structure.sql exists (schema_format = :sql)' do
      let(:schema_rb_exists) { false }
      let(:structure_sql_exists) { true }

      it 'returns a pass check naming structure.sql' do
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to eq('db/structure.sql found')
      end
    end

    context 'when db/schema.rb takes precedence over db/structure.sql' do
      let(:schema_rb_exists) { true }
      let(:structure_sql_exists) { true }

      it 'reports schema.rb' do
        expect(checker.call.message).to eq('db/schema.rb found')
      end
    end

    context 'when neither schema file exists' do
      let(:schema_rb_exists) { false }
      let(:structure_sql_exists) { false }

      it 'returns a warn check that mentions both files' do
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to eq('db/schema.rb or db/structure.sql not found')
        expect(result.fix).to include('rails db:migrate')
      end
    end
  end
end
