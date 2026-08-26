# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

# Characterization specs that pin the MCP tool annotation structure across
# all 19 built-in tools. The MCP SDK's `annotations` DSL exposes hints that
# clients use to understand tool safety characteristics.
#
# All rails-ai-bridge tools are read-only, non-destructive, and idempotent
# with open_world_hint: false — except GetProviderContext, which is
# idempotent_hint: false (provider data may change between calls) and
# open_world_hint: true (it reaches external services). These specs pin
# that contract so the MCP 1.3.0 upgrade doesn't silently change it.
#
# In MCP SDK 1.3.0, `annotations` returns an `MCP::Tool::Annotations` object
# with accessor methods (not a Hash), and `input_schema` returns an
# `MCP::Tool::InputSchema` object.
RSpec.describe 'MCP tool annotations (SDK 1.3.0)' do
  RailsAiBridge::Server::TOOLS.each do |tool_class|
    describe "#{tool_class} annotations" do
      it 'is a subclass of MCP::Tool' do
        expect(tool_class.ancestors).to include(MCP::Tool)
      end

      it 'has a tool_name prefixed with rails_' do
        expect(tool_class.tool_name).to start_with('rails_')
      end

      it 'has a non-empty description' do
        expect(tool_class.description).to be_present
      end

      it 'has an input_schema object' do
        expect(tool_class.input_schema).to respond_to(:to_h)
      end

      it 'declares read_only_hint: true' do
        expect(tool_class.annotations.read_only_hint).to be(true)
      end

      it 'declares destructive_hint: false' do
        expect(tool_class.annotations.destructive_hint).to be(false)
      end

      it 'declares idempotent_hint: true (or false for outbound providers)' do
        if tool_class == RailsAiBridge::Tools::GetProviderContext
          expect(tool_class.annotations.idempotent_hint).to be(false)
        else
          expect(tool_class.annotations.idempotent_hint).to be(true)
        end
      end

      it 'declares open_world_hint: false (or true for outbound providers)' do
        if tool_class == RailsAiBridge::Tools::GetProviderContext
          expect(tool_class.annotations.open_world_hint).to be(true)
        else
          expect(tool_class.annotations.open_world_hint).to be(false)
        end
      end
    end
  end

  describe 'annotation keys present on every tool' do
    it 'includes all four hint keys in to_h (camelCase per MCP spec)' do
      RailsAiBridge::Server::TOOLS.each do |tool_class|
        hash = tool_class.annotations.to_h
        expect(hash).to include(:readOnlyHint, :destructiveHint, :idempotentHint, :openWorldHint)
      end
    end
  end

  describe 'MCP::Tool::Response construction' do
    it 'builds a response from a text content array' do
      response = MCP::Tool::Response.new([{ type: 'text', text: 'hello' }])

      expect(response).to respond_to(:to_h)
      expect(response).to respond_to(:content)
      expect(response.content).to be_an(Array)
    end

    it 'serializes to a hash' do
      response = MCP::Tool::Response.new([{ type: 'text', text: 'data' }])
      hash = response.to_h

      expect(hash).to be_a(Hash)
    end

    it 'is not an error response by default' do
      response = MCP::Tool::Response.new([{ type: 'text', text: 'ok' }])

      expect(response.error?).to be(false)
    end
  end

  describe 'BaseTool.text_response truncation bounds' do
    before do
      allow(RailsAiBridge.configuration).to receive(:max_tool_response_chars).and_return(100)
    end

    it 'returns text as-is when under the limit' do
      response = RailsAiBridge::Tools::BaseTool.text_response('short text')

      expect(response.content.first[:text]).to eq('short text')
    end

    it 'truncates text and appends a suffix when over the limit' do
      long_text = 'x' * 200
      response = RailsAiBridge::Tools::BaseTool.text_response(long_text)

      text = response.content.first[:text]
      expect(text.length).to be <= 100
      expect(text).to include('Response truncated')
    end

    it 'returns an MCP::Tool::Response instance' do
      response = RailsAiBridge::Tools::BaseTool.text_response('text')

      expect(response).to be_a(MCP::Tool::Response)
    end
  end

  describe 'BaseTool.text_response without truncation limit' do
    before do
      allow(RailsAiBridge.configuration).to receive(:max_tool_response_chars).and_return(nil)
    end

    it 'returns full text without truncation' do
      long_text = 'x' * 10_000
      response = RailsAiBridge::Tools::BaseTool.text_response(long_text)

      expect(response.content.first[:text]).to eq(long_text)
    end
  end
end
