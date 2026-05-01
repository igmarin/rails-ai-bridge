# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP large payload stability' do
  let(:large_schema) do
    tables = 80.times.to_h do |index|
      ["table_#{index.to_s.rjust(3, '0')}", {
        columns: 25.times.map { |column| { name: "column_#{column}", type: 'string', null: true } },
        indexes: [{ name: "index_table_#{index}_on_column_0", columns: ['column_0'], unique: false }],
        foreign_keys: []
      }]
    end

    { adapter: 'postgresql', total_tables: tables.size, tables: tables }
  end

  let(:large_routes) do
    by_controller = 40.times.to_h do |controller|
      ["controller_#{controller.to_s.rjust(2, '0')}", 8.times.map do |action|
        {
          verb: 'GET',
          path: "/controller_#{controller}/action_#{action}",
          action: "action_#{action}",
          name: "controller_#{controller}_action_#{action}"
        }
      end]
    end

    { total_routes: 320, by_controller: by_controller, api_namespaces: [] }
  end

  before do
    RailsAiBridge::ContextProvider.reset!
    allow(RailsAiBridge::Fingerprinter).to receive(:snapshot).and_return('large-payload-fingerprint')
    allow(RailsAiBridge).to receive(:introspect) do |_app, only: nil|
      case only
      when [:schema] then { schema: large_schema }
      when [:routes] then { routes: large_routes }
      else { schema: large_schema, routes: large_routes }
      end
    end
  end

  after do
    RailsAiBridge::ContextProvider.reset!
  end

  it 'truncates oversized MCP responses while preserving pagination guidance' do
    original_max = RailsAiBridge.configuration.max_tool_response_chars
    RailsAiBridge.configuration.max_tool_response_chars = 800

    response = RailsAiBridge::Tools::GetSchema.call(detail: 'full', format: 'json')
    text = response.content.first[:text]

    expect(text.length).to be <= 800
    expect(text).to include('Response truncated')
    expect(text).to include('detail:"summary"')
  ensure
    RailsAiBridge.configuration.max_tool_response_chars = original_max
  end

  it 'paginates large schema payloads with stable next-offset guidance' do
    response = RailsAiBridge::Tools::GetSchema.call(detail: 'summary', limit: 10, offset: 20)
    text = response.content.first[:text]

    expect(text).to include('table_020')
    expect(text).not_to include('table_019')
    expect(text).to include('Use `offset:30` for more')
  end

  it 'paginates large route payloads with stable next-offset guidance' do
    response = RailsAiBridge::Tools::GetRoutes.call(detail: 'standard', limit: 10, offset: 20)
    text = response.content.first[:text]

    expect(text).to include('/controller_2/action_4')
    expect(text).not_to include('/controller_0/action_0')
    expect(text).to include('Use `offset:30` for more')
  end

  it 'reuses cached large sections across repeated MCP tool calls' do
    2.times { RailsAiBridge::Tools::GetSchema.call(detail: 'summary', limit: 5) }
    2.times { RailsAiBridge::Tools::GetRoutes.call(detail: 'summary') }

    expect(RailsAiBridge).to have_received(:introspect).with(Rails.application, only: [:schema]).once
    expect(RailsAiBridge).to have_received(:introspect).with(Rails.application, only: [:routes]).once
  end
end
