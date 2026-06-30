# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Instrumentation do
  describe '.instrument' do
    it 'yields when ActiveSupport::Notifications is unavailable' do
      stub_const('ActiveSupport::Notifications', nil)

      result = described_class.instrument('tool.call', tool_name: 'test') { 42 }
      expect(result).to eq(42)
    end

    it 'instruments through ActiveSupport::Notifications when available' do
      events = []
      callback = ->(name, _started, _finished, _unique_id, payload) { events << [name, payload] }

      ActiveSupport::Notifications.subscribed(callback, 'rails_ai_bridge.tool.call') do
        described_class.instrument('tool.call', tool_name: 'test') { 'done' }
      end

      expect(events.size).to eq(1)
      expect(events.first.first).to eq('rails_ai_bridge.tool.call')
      expect(events.first.last[:tool_name]).to eq('test')
    end
  end

  describe 'InstrumentedTool' do
    let(:tool_class) do
      Class.new(RailsAiBridge::Tools::BaseTool) do
        tool_name 'rails_test_tool'
        description 'Test'
        input_schema(properties: {})

        def self.call(**)
          MCP::Tool::Response.new([{ type: 'text', text: 'ok' }])
        end
      end
    end

    it 'emits rails_ai_bridge.tool.call on invocation' do
      events = []
      callback = ->(name, _started, _finished, _unique_id, payload) { events << [name, payload] }

      ActiveSupport::Notifications.subscribed(callback, 'rails_ai_bridge.tool.call') do
        described_class::InstrumentedTool.new(tool_class).call(value: 1)
      end

      expect(events.size).to eq(1)
      expect(events.first.first).to eq('rails_ai_bridge.tool.call')
      expect(events.first.last[:tool_name]).to eq('rails_test_tool')
      expect(events.first.last[:arguments]).to eq({ value: 1 })
    end
  end
end
