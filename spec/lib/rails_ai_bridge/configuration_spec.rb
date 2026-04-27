# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Configuration do
  let(:config) { described_class.new }

  it 'has sensible defaults' do
    expect(config.server_name).to eq('rails-ai-bridge')
    expect(config.http_port).to eq(6029)
    expect(config.http_bind).to eq('127.0.0.1')
    expect(config.auto_mount).to be(false)
    expect(config.allow_auto_mount_in_production).to be(false)
    expect(config.http_mcp_token).to be_nil
    expect(config.search_code_allowed_file_types).to eq([])
    expect(config.expose_credentials_key_names).to be(false)
    expect(config.cache_ttl).to eq(30)
    expect(config.context_mode).to eq(:compact)
    expect(config.claude_max_lines).to eq(150)
    expect(config.max_tool_response_chars).to eq(120_000)
    expect(config.assistant_overrides_path).to be_nil
    expect(config.copilot_compact_model_list_limit).to eq(5)
    expect(config.codex_compact_model_list_limit).to eq(3)
    expect(config.additional_introspectors).to eq({})
    expect(config.additional_tools).to eq([])
    expect(config.additional_resources).to eq({})
    expect(config.core_models).to eq([])
    expect(config.mcp_token_resolver).to be_nil
    expect(config.mcp_jwt_decoder).to be_nil
    expect(config.rate_limit_max_requests).to be_nil
    expect(config.rate_limit_window_seconds).to eq(60)
    expect(config.http_log_json).to be(false)
  end

  it 'exposes the mcp sub-config' do
    expect(config.mcp).to be_a(RailsAiBridge::Config::Mcp)
  end

  it 'defaults to standard preset' do
    expect(config.introspectors).to eq(described_class::PRESETS[:standard])
  end

  it 'excludes internal Rails models by default' do
    expect(config.excluded_models).to include('ApplicationRecord')
    expect(config.excluded_models).to include('ActiveStorage::Blob')
  end

  it 'is configurable' do
    config.server_name = 'my-app'
    config.http_port = 8080
    config.auto_mount = true

    expect(config.server_name).to eq('my-app')
    expect(config.http_port).to eq(8080)
    expect(config.auto_mount).to be(true)
  end

  describe '#preset=' do
    it 'sets introspectors to standard preset' do
      config.preset = :standard
      expect(config.introspectors).to eq(%i[schema models routes jobs gems conventions controllers tests migrations])
    end

    it 'sets introspectors to full preset' do
      config.preset = :full
      expect(config.introspectors.size).to eq(27)
      expect(config.introspectors).to include(:stimulus, :views, :turbo, :auth, :api, :devops, :migrations, :seeds,
                                              :middleware, :engines, :multi_database, :non_ar_models)
    end

    it 'accepts string preset names' do
      config.preset = 'full'
      expect(config.introspectors.size).to eq(27)
    end

    it 'raises on unknown preset' do
      expect { config.preset = :unknown }.to raise_error(ArgumentError, /Unknown preset/)
    end

    it 'sets regulated preset without schema, models, or migrations' do
      config.preset = :regulated
      expect(config.introspectors).not_to include(:schema, :models, :migrations)
      expect(config.introspectors).to include(:routes, :controllers)
    end

    it 'allows adding introspectors after preset' do
      config.preset = :standard
      config.introspectors += %i[views turbo]
      expect(config.introspectors).to include(:views, :turbo)
      expect(config.introspectors.size).to eq(11)
    end
  end

  describe '#effective_introspectors' do
    it 'returns all introspectors when no categories disabled' do
      config.preset = :standard
      expect(config.effective_introspectors).to eq(config.introspectors)
    end

    it 'subtracts disabled categories' do
      config.preset = :standard
      config.disabled_introspection_categories << :domain_metadata
      effective = config.effective_introspectors
      expect(effective).not_to include(:schema, :models, :non_ar_models, :migrations)
      expect(effective).to include(:routes, :controllers, :gems)
    end

    it 'handles multiple disabled categories' do
      config.preset = :full
      config.disabled_introspection_categories = %i[domain_metadata ui_stack]
      effective = config.effective_introspectors
      expect(effective).not_to include(:schema, :models, :non_ar_models, :migrations, :views, :stimulus, :turbo, :i18n)
      expect(effective).to include(:routes, :controllers, :gems, :jobs, :tests)
    end

    it 'ignores unknown category names' do
      config.preset = :standard
      config.disabled_introspection_categories << :nonexistent
      expect(config.effective_introspectors).to eq(config.introspectors)
    end
  end

  describe '#excluded_table?' do
    it 'returns false for nil or empty' do
      expect(config.excluded_table?(nil)).to be false
      expect(config.excluded_table?('')).to be false
    end

    it 'matches exact table names' do
      config.excluded_tables << 'secrets'
      expect(config.excluded_table?('secrets')).to be true
      expect(config.excluded_table?('users')).to be false
    end

    it 'matches glob patterns' do
      config.excluded_tables << 'audit_*'
      expect(config.excluded_table?('audit_logs')).to be true
      expect(config.excluded_table?('audit_events')).to be true
      expect(config.excluded_table?('users')).to be false
    end

    it 'returns false when excluded_tables is empty' do
      expect(config.excluded_table?('anything')).to be false
    end
  end

  describe 'extensibility registries' do
    it 'allows registering an additional introspector' do
      config.additional_introspectors[:custom] = Class.new

      expect(config.additional_introspectors.keys).to include(:custom)
    end

    it 'allows registering additional MCP tools' do
      tool_class = Class.new
      config.additional_tools << tool_class

      expect(config.additional_tools).to include(tool_class)
    end

    it 'allows registering additional resources' do
      config.additional_resources['rails://custom'] = {
        name: 'Custom',
        description: 'Custom resource',
        mime_type: 'application/json',
        key: :custom
      }

      expect(config.additional_resources).to have_key('rails://custom')
    end
  end

  describe 'Fix #2: preset reader on facade' do
    it 'exposes a preset reader via delegation' do
      expect(config.respond_to?(:preset)).to be(true)
    end

    it 'returns nil before any preset is explicitly set' do
      expect(config.preset).to be_nil
    end

    it 'returns the preset name after setting it' do
      config.preset = :full
      expect(config.preset).to eq(:full)
    end
  end

  describe RailsAiBridge do
    it 'supports block configuration' do
      described_class.configure do |c|
        c.server_name = 'test-app'
      end

      expect(described_class.configuration.server_name).to eq('test-app')
    ensure
      # Reset
      described_class.configuration = RailsAiBridge::Configuration.new
    end
  end
end
