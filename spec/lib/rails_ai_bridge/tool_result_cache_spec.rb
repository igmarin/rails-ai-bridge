# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::ToolResultCache do
  around do |example|
    original_ttl = RailsAiBridge.configuration.mcp.tool_result_cache_ttl
    described_class.reset!
    example.run
  ensure
    RailsAiBridge.configuration.mcp.tool_result_cache_ttl = original_ttl
    described_class.reset!
  end

  describe '.enabled?' do
    it 'is disabled when ttl is 0' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 0
      expect(described_class).not_to be_enabled
    end

    it 'is enabled when ttl is positive' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      expect(described_class).to be_enabled
    end
  end

  describe '.fetch_response' do
    let(:response) { MCP::Tool::Response.new([{ type: 'text', text: 'hello' }]) }

    it 'returns yielded response when caching is disabled' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 0
      calls = 0

      result = described_class.fetch_response('rails_test', { 'key' => 'value' }) do
        calls += 1
        response
      end

      expect(result).to eq(response)
      expect(calls).to eq(1)

      described_class.fetch_response('rails_test', { 'key' => 'value' }) do
        calls += 1
        response
      end
      expect(calls).to eq(2)
    end

    it 'caches yielded responses by tool name and argument fingerprint' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      calls = 0

      2.times do
        result = described_class.fetch_response('rails_test', { key: 'value' }) do
          calls += 1
          response
        end
        expect(result).to eq(response)
      end

      expect(calls).to eq(1)
    end

    it 'produces different keys for different arguments' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      calls = 0

      described_class.fetch_response('rails_test', { key: 'a' }) do
        calls += 1
        response
      end
      described_class.fetch_response('rails_test', { key: 'b' }) do
        calls += 1
        response
      end

      expect(calls).to eq(2)
    end

    it 'produces different keys for different tools' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      calls = 0

      described_class.fetch_response('rails_one', { key: 'value' }) do
        calls += 1
        response
      end
      described_class.fetch_response('rails_two', { key: 'value' }) do
        calls += 1
        response
      end

      expect(calls).to eq(2)
    end

    it 'expires entries after the configured ttl' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 0.01
      calls = 0

      described_class.fetch_response('rails_test', { key: 'value' }) do
        calls += 1
        response
      end
      sleep(0.02)
      described_class.fetch_response('rails_test', { key: 'value' }) do
        calls += 1
        response
      end

      expect(calls).to eq(2)
    end

    it 'emits a cache hit event for cached responses' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      events = []
      callback = ->(name, _started, _finished, _unique_id, payload) { events << [name, payload] }

      ActiveSupport::Notifications.subscribed(callback, 'rails_ai_bridge.tool.result_cache_hit') do
        described_class.fetch_response('rails_test', { key: 'value' }) { response }
        described_class.fetch_response('rails_test', { key: 'value' }) { response }
      end

      expect(events.size).to eq(1)
      expect(events.first.first).to eq('rails_ai_bridge.tool.result_cache_hit')
      expect(events.first.last[:tool_name]).to eq('rails_test')
      expect(events.first.last[:fingerprint]).to be_a(String)
    end

    it 'emits a cache miss event for fresh responses' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      events = []
      callback = ->(name, _started, _finished, _unique_id, payload) { events << [name, payload] }

      ActiveSupport::Notifications.subscribed(callback, 'rails_ai_bridge.tool.result_cache_miss') do
        described_class.fetch_response('rails_test', { key: 'value' }) { response }
      end

      expect(events.size).to eq(1)
      expect(events.first.first).to eq('rails_ai_bridge.tool.result_cache_miss')
      expect(events.first.last[:tool_name]).to eq('rails_test')
    end
  end

  describe '.maybe_wrap' do
    let(:tool_class) do
      Class.new(RailsAiBridge::Tools::BaseTool) do
        tool_name 'rails_cached_demo'
        description 'Demo'
        input_schema(properties: {})

        def self.call(**)
          MCP::Tool::Response.new([{ type: 'text', text: 'ok' }])
        end
      end
    end

    it 'returns the original class when caching is disabled' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 0
      expect(described_class.maybe_wrap(tool_class)).to eq(tool_class)
    end

    it 'returns a cached wrapper when caching is enabled' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      wrapped = described_class.maybe_wrap(tool_class)

      expect(wrapped).to be_a(described_class::CachedTool)
      expect(wrapped.tool_name).to eq('rails_cached_demo')
    end

    it 'caches calls through the wrapper' do
      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      wrapped = described_class.maybe_wrap(tool_class)
      calls = 0

      allow(tool_class).to receive(:call).and_wrap_original do
        calls += 1
        MCP::Tool::Response.new([{ type: 'text', text: 'ok' }])
      end

      2.times { wrapped.call(key: 'value') }

      expect(calls).to eq(1)
    end

    it 'passes server_context when the wrapped tool accepts it' do
      ctx_tool = Class.new(RailsAiBridge::Tools::BaseTool) do
        tool_name 'rails_ctx_demo'
        description 'Demo'
        input_schema(properties: {})

        def self.call(server_context: nil, **)
          MCP::Tool::Response.new([{ type: 'text', text: server_context.to_s }])
        end
      end

      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      wrapped = described_class.maybe_wrap(ctx_tool)
      context = { request_id: '123' }

      result = wrapped.call(server_context: context)

      expect(result.content.first[:text]).to eq(context.to_s)
    end

    it 'translates server_context for tools that use _server_context' do
      underscore_tool = Class.new(RailsAiBridge::Tools::BaseTool) do
        tool_name 'rails_underscore_demo'
        description 'Demo'
        input_schema(properties: {})

        def self.call(ctx: nil, **)
          MCP::Tool::Response.new([{ type: 'text', text: ctx.to_s }])
        end
      end

      allow(underscore_tool).to receive(:method).with(:call).and_return(
        double(parameters: [%i[key _server_context], %i[keyrest kwargs]])
      )

      RailsAiBridge.configuration.mcp.tool_result_cache_ttl = 30
      wrapped = described_class.maybe_wrap(underscore_tool)
      context = { request_id: '456' }

      expect(underscore_tool).to receive(:call).with(_server_context: context).and_return(
        MCP::Tool::Response.new([{ type: 'text', text: context.to_s }])
      )

      result = wrapped.call(server_context: context)

      expect(result.content.first[:text]).to eq(context.to_s)
    end
  end
end
