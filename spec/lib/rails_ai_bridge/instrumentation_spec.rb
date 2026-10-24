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

    let(:events) { [] }
    let(:subscriber) { ->(*args) { events << ActiveSupport::Notifications::Event.new(*args) } }
    let(:instrumented_tool) { described_class::InstrumentedTool.new(tool_class) }
    let(:response_class) do
      tool_class # Load BaseTool and the MCP SDK regardless of randomized example order.
      MCP::Tool::Response
    end

    it 'records the success outcome of an MCP response' do
      ActiveSupport::Notifications.subscribed(subscriber, 'rails_ai_bridge.tool.call') do
        instrumented_tool.call(value: 1)
      end

      expect(events.fetch(0).payload).to include(success: true, error_class: nil)
    end

    it 'records the class of a raised exception before notifying subscribers' do
      failure = ArgumentError.new('synthetic failure')
      allow(tool_class).to receive(:call).and_raise(failure)

      expect do
        ActiveSupport::Notifications.subscribed(subscriber, 'rails_ai_bridge.tool.call') do
          instrumented_tool.call(value: 1)
        end
      end.to(raise_error { |actual| expect(actual).to equal(failure) })

      expect(events.fetch(0).payload).to include(success: false, error_class: 'ArgumentError')
    end

    it 'reports an SDK error response without inventing an exception class' do
      response = response_class.new([{ type: 'text', text: 'synthetic failure' }], error: true).freeze
      original = response.to_h
      allow(tool_class).to receive(:call).and_return(response)
      returned = nil

      ActiveSupport::Notifications.subscribed(subscriber, 'rails_ai_bridge.tool.call') do
        returned = instrumented_tool.call(value: 1)
      end

      expect(returned).to equal(response)
      expect(response.to_h).to eq(original)
      expect(events.fetch(0).payload).to include(success: false, error_class: nil)
    end

    it 'does not infer an error from response text' do
      response = response_class.new([{ type: 'text', text: '{"error":"example documentation"}' }]).freeze
      allow(tool_class).to receive(:call).and_return(response)
      returned = nil

      ActiveSupport::Notifications.subscribed(subscriber, 'rails_ai_bridge.tool.call') do
        returned = instrumented_tool.call(value: 1)
      end

      expect(returned).to equal(response)
      expect(events.fetch(0).payload).to include(success: true, error_class: nil)
    end

    it 'keeps duration available to standard notification subscribers' do
      ActiveSupport::Notifications.subscribed(subscriber, 'rails_ai_bridge.tool.call') do
        instrumented_tool.call(value: 1)
      end

      expect(events.fetch(0).duration).to be >= 0
    end

    it 'adds only success and exception class to the existing payload' do
      ActiveSupport::Notifications.subscribed(subscriber, 'rails_ai_bridge.tool.call') do
        instrumented_tool.call(sql: 'synthetic private argument')
      end

      payload = events.fetch(0).payload
      expect(payload.except(:arguments, :tool_name)).to eq(success: true, error_class: nil)
      expect(payload[:arguments]).to eq(sql: 'synthetic private argument')
    end

    context 'when tool results are cached' do
      around do |example|
        previous_ttl = RailsAiBridge.configuration.mcp.tool_result_cache_ttl
        RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
        RailsAiBridge::ToolResultCache.reset!
        example.run
      ensure
        RailsAiBridge.configuration.mcp.tool_result_cache_ttl = previous_ttl
        RailsAiBridge::ToolResultCache.reset!
      end

      it 'reports each invocation while preserving cache hit and miss events' do
        response = response_class.new([{ type: 'text', text: 'ok' }]).freeze
        allow(tool_class).to receive(:call).and_return(response)
        cached_tool = described_class::InstrumentedTool.new(RailsAiBridge::ToolResultCache.maybe_wrap(tool_class))
        returned = []

        ActiveSupport::Notifications.subscribed(subscriber, /\Arails_ai_bridge\.tool\./) do
          2.times { returned << cached_tool.call(value: 1) }
        end

        calls = events.select { |event| event.name == 'rails_ai_bridge.tool.call' }
        expect(calls.size).to eq(2)
        expect(calls.map { |event| event.payload.slice(:success, :error_class) }).to all(eq(success: true, error_class: nil))
        expect(events.map(&:name)).to include('rails_ai_bridge.tool.result_cache_miss', 'rails_ai_bridge.tool.result_cache_hit')
        expect(returned).to all(equal(response))
        expect(tool_class).to have_received(:call).once
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
