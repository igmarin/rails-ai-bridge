# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::Collaborators::RulesStackOverviewBuilder do
  subject(:builder) { described_class.new(context) }

  let(:context) do
    {
      app_name: 'Acme',
      rails_version: '8.1.4',
      ruby_version: '4.0.10',
      environment: 'development',
      database_adapter: 'postgresql'
    }
  end

  describe '#call' do
    it 'renders heading plus one line per populated field' do
      expect(builder.call).to eq([
                                   '## Application Stack & Overview',
                                   '- **Name:** `Acme`',
                                   '- **Rails:** `8.1.4`',
                                   '- **Ruby:** `4.0.10`',
                                   '- **Environment:** `development`',
                                   '- **Database:** `postgresql`'
                                 ])
    end

    it 'omits missing fields and keeps the rest' do
      result = described_class.new(context.slice(:app_name, :rails_version)).call

      expect(result).to eq([
                             '## Application Stack & Overview',
                             '- **Name:** `Acme`',
                             '- **Rails:** `8.1.4`'
                           ])
    end

    it 'returns empty when no metadata exists' do
      expect(described_class.new({}).call).to eq([])
    end

    it 'returns empty when every field is present? false' do
      expect(described_class.new({ app_name: '', ruby_version: nil }).call).to eq([])
    end
  end
end
