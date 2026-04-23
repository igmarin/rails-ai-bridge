# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Doctor::Checkers::SchemaChecker do
  let(:app) { Rails.application }
  let(:checker) { described_class.new(app) }

  describe '#call' do
    let(:schema_path) { File.join(app.root, 'db/schema.rb') }

    context 'when db/schema.rb exists' do
      before { allow(File).to receive(:exist?).with(schema_path).and_return(true) }

      it 'returns a pass check' do
        result = checker.call
        expect(result.status).to eq(:pass)
        expect(result.message).to eq('db/schema.rb found')
      end
    end

    context 'when db/schema.rb does not exist' do
      before { allow(File).to receive(:exist?).with(schema_path).and_return(false) }

      it 'returns a warn check' do
        result = checker.call
        expect(result.status).to eq(:warn)
        expect(result.message).to eq('db/schema.rb not found')
        expect(result.fix).to include('rails db:schema:dump')
      end
    end
  end
end
