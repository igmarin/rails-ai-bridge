# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/serializers/formatters/sections/config_formatter'

RSpec.describe RailsAiBridge::Serializers::Formatters::Sections::ConfigFormatter do
  describe '#call' do
    it 'returns nil when data is empty' do
      formatter = described_class.new({})
      expect(formatter.call).to be_nil
    end

    it 'renders configuration properly' do
      data = {
        cache_store: 'redis_cache_store',
        session_store: 'cookie_store',
        timezone: 'UTC',
        middleware_stack: ['Rack::Cors', 'Rack::Timeout'],
        initializers: ['cors.rb'],
        current_attributes: ['Current']
      }
      formatter = described_class.new({ config: data })
      result = formatter.call

      expect(result).to include('## Application Configuration')
      expect(result).to include('- **Cache store:** `redis_cache_store`')
      expect(result).to include('- **Session store:** `cookie_store`')
      expect(result).to include('- **Timezone:** `UTC`')
      expect(result).to include('### Middleware Stack')
      expect(result).to include('- `Rack::Cors`')
      expect(result).to include('### Initializers')
      expect(result).to include('- `cors.rb`')
      expect(result).to include('### CurrentAttributes')
      expect(result).to include('- `Current`')
    end
  end
end
