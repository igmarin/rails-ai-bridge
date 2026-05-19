# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/serializers/formatters/sections/views_formatter'

RSpec.describe RailsAiBridge::Serializers::Formatters::Sections::ViewsFormatter do
  describe '#call' do
    it 'returns nil when data is empty' do
      formatter = described_class.new({})
      expect(formatter.call).to be_nil
    end

    it 'renders views properly' do
      data = {
        layouts: ['application'],
        template_engines: ['erb'],
        templates: { 'users' => %w[index show] },
        helpers: [{ file: 'users_helper.rb', methods: ['format_name'] }],
        view_components: ['ButtonComponent']
      }
      formatter = described_class.new({ views: data })
      result = formatter.call

      expect(result).to include('## Views')
      expect(result).to include('- Layouts: application')
      expect(result).to include('- Template engines: erb')
      expect(result).to include('### Templates by controller')
      expect(result).to include('- `users/`: index, show')
      expect(result).to include('### Helpers')
      expect(result).to include('- `users_helper.rb`: format_name')
      expect(result).to include('- View components: 1')
    end
  end
end
