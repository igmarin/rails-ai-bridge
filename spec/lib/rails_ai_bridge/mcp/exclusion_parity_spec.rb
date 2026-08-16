# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../support/real_fixture_app_context'

# Ensure Combustion models are loaded so live exclusion checks see them.
require_relative '../../../internal/app/models/application_record'
require_relative '../../../internal/app/models/user'
require_relative '../../../internal/app/models/post'
require_relative '../../../internal/app/models/category'
require_relative '../../../internal/app/models/categorization'
require_relative '../../../internal/app/models/group'
require_relative '../../../internal/app/models/membership'

# Parity tables for MCP exclusion coverage. When Server::TOOLS or resource
# templates grow, add the new entry here or this spec fails.
#
# Composite +rails_get_context+ does not exist yet (issue #181). When that
# tool ships, add it to TOOL_EXCLUSION_POLICY as +:omits_excluded_names+ and
# remove it from PENDING_COMPOSITE_TOOLS.
module MCPExclusionParityTables
  # Policy for every Server::TOOLS entry.
  # :omits_excluded_names — invoked; omitted names must not appear.
  # :source_search — filesystem/semantic search, not a schema/model listing.
  # :does_not_list_models_or_tables — no introspected model/table inventory.
  # None of the schema/model/route/controller surfaces are unfiltered.
  TOOL_EXCLUSION_POLICY = {
    'rails_get_schema' => :omits_excluded_names,
    'rails_get_routes' => :omits_excluded_names,
    'rails_get_model_details' => :omits_excluded_names,
    'rails_get_gems' => :does_not_list_models_or_tables,
    'rails_search_code' => :source_search,
    'rails_search_semantic' => :source_search,
    'rails_get_conventions' => :omits_excluded_names,
    'rails_get_controllers' => :omits_excluded_names,
    'rails_get_config' => :does_not_list_models_or_tables,
    'rails_get_test_info' => :does_not_list_models_or_tables,
    'rails_get_view' => :does_not_list_models_or_tables,
    'rails_get_stimulus' => :does_not_list_models_or_tables,
    'rails_list_registry' => :does_not_list_models_or_tables,
    'rails_resolve_skill' => :does_not_list_models_or_tables,
    'rails_use_skill' => :does_not_list_models_or_tables,
    'rails_use_agent' => :does_not_list_models_or_tables,
    'rails_list_context_providers' => :does_not_list_models_or_tables
  }.freeze

  PENDING_COMPOSITE_TOOLS = %w[rails_get_context].freeze

  RESOURCE_TEMPLATE_POLICY = {
    'rails://models/{name}' => :omits_excluded_names,
    'rails://views/{path}' => :does_not_list_models_or_tables,
    'rails://stimulus/{name}' => :does_not_list_models_or_tables,
    'rails://context-providers/{name}' => :does_not_list_models_or_tables
  }.freeze

  STATIC_RESOURCE_POLICY = {
    'rails://bridge/meta' => :does_not_list_models_or_tables,
    'rails://schema' => :omits_excluded_names,
    'rails://routes' => :omits_excluded_names,
    'rails://conventions' => :omits_excluded_names,
    'rails://gems' => :does_not_list_models_or_tables,
    'rails://controllers' => :omits_excluded_names,
    'rails://config' => :does_not_list_models_or_tables,
    'rails://tests' => :does_not_list_models_or_tables,
    'rails://migrations' => :omits_excluded_names,
    'rails://engines' => :does_not_list_models_or_tables,
    'rails://views' => :does_not_list_models_or_tables,
    'rails://stimulus' => :does_not_list_models_or_tables,
    'rails://semantic/analysis' => :does_not_list_models_or_tables
  }.freeze

  EXCLUDED_MODEL = 'Categorization'
  EXCLUDED_TABLE = 'categorizations'

  # Routes/controllers stay enabled under :regulated and may name /users.
  DOMAIN_METADATA_TOOL_NAMES = %w[rails_get_schema rails_get_model_details].freeze
  DOMAIN_METADATA_RESOURCE_URIS = %w[rails://schema rails://migrations].freeze
  DOMAIN_METADATA_NAMES = %w[
    User Post Category Categorization Group Membership
    users posts categories categorizations groups memberships
  ].freeze

  REGULATED_FIXTURE_NAMES = %w[PatientRecord patient_records ssn_digest].freeze
end

# Guard: excluded_models, excluded_tables, :regulated, and
# disabled_introspection_categories must apply to every built-in MCP tool and
# rails:// resource that can name models or tables.
RSpec.describe 'MCP exclusion parity' do
  let(:config) { RailsAiBridge.configuration }

  around do |example|
    original = {
      introspectors: config.introspectors.dup,
      excluded_models: config.excluded_models.dup,
      excluded_tables: config.excluded_tables.dup,
      disabled_categories: config.disabled_introspection_categories.dup,
      preset: config.preset
    }
    RailsAiBridge::ContextProvider.reset!
    example.run
  ensure
    if original[:preset]
      config.preset = original[:preset]
    else
      config.introspectors = original[:introspectors]
    end
    config.excluded_models = original[:excluded_models]
    config.excluded_tables = original[:excluded_tables]
    config.disabled_introspection_categories = original[:disabled_categories]
    RailsAiBridge::ContextProvider.reset!
  end

  describe 'parity tables' do
    it 'lists every Server::TOOLS entry' do
      registered = RailsAiBridge::Server::TOOLS.map(&:tool_name)
      expect(MCPExclusionParityTables::TOOL_EXCLUSION_POLICY.keys).to match_array(registered),
                                                                      'Add the new tool to TOOL_EXCLUSION_POLICY ' \
                                                                      '(or PENDING_COMPOSITE_TOOLS is stale).'
    end

    it 'lists every resource template' do
      templates = RailsAiBridge::Resources.build_templates.map(&:uri_template)
      expect(MCPExclusionParityTables::RESOURCE_TEMPLATE_POLICY.keys).to match_array(templates),
                                                                         'Add the new resource template to RESOURCE_TEMPLATE_POLICY.'
    end

    it 'lists every static resource URI' do
      expect(MCPExclusionParityTables::STATIC_RESOURCE_POLICY.keys)
        .to match_array(RailsAiBridge::Resources::STATIC_RESOURCES.keys),
            'Add the new static resource to STATIC_RESOURCE_POLICY.'
    end

    # rails_get_context does not exist yet — skip/allowlist it until #181.
    it 'allowlists rails_get_context until issue #181' do
      pending_tools = MCPExclusionParityTables::PENDING_COMPOSITE_TOOLS
      expect(pending_tools).to include('rails_get_context')
      registered = RailsAiBridge::Server::TOOLS.map(&:tool_name)
      shipped = pending_tools & registered
      expect(shipped).to be_empty,
                         "#{shipped.join(', ')} is now in Server::TOOLS — add it to " \
                         'TOOL_EXCLUSION_POLICY as :omits_excluded_names and remove it ' \
                         'from PENDING_COMPOSITE_TOOLS.'
    end
  end

  describe 'excluded_models and excluded_tables' do
    before do
      config.excluded_models += [MCPExclusionParityTables::EXCLUDED_MODEL]
      config.excluded_tables += [MCPExclusionParityTables::EXCLUDED_TABLE]
      RailsAiBridge::ContextProvider.reset!
    end

    it 'omits excluded names from listing tools that can name models or tables' do
      model_name = MCPExclusionParityTables::EXCLUDED_MODEL
      table_name = MCPExclusionParityTables::EXCLUDED_TABLE
      listing_tools.each do |tool_class|
        invoke_tool(tool_class).each do |body|
          expect(body).not_to include(model_name), "#{tool_class.tool_name} leaked #{model_name}"
          expect(body).not_to include(table_name), "#{tool_class.tool_name} leaked #{table_name}"
        end
      end
    end

    it 'omits excluded names from rails:// listing resources' do
      model_name = MCPExclusionParityTables::EXCLUDED_MODEL
      table_name = MCPExclusionParityTables::EXCLUDED_TABLE
      listing_resource_uris.each do |uri|
        body = resource_body(uri)
        expect(body).not_to include(model_name), "#{uri} leaked #{model_name}"
        expect(body).not_to include(table_name), "#{uri} leaked #{table_name}"
      end
    end

    it 'does not return details for an excluded model resource' do
      model_name = MCPExclusionParityTables::EXCLUDED_MODEL
      payload = RailsAiBridge::Resources.send(:resolve_resource_payload, "rails://models/#{model_name}")
      expect(payload).to eq(error: "Model '#{model_name}' not found")
    end

    it 'does not treat an excluded table as found' do
      table_name = MCPExclusionParityTables::EXCLUDED_TABLE
      body = tool_text(RailsAiBridge::Tools::GetSchema, table: table_name)
      expect(body).to include('not found')
      expect(body).not_to include("## Table: #{table_name}")
      expect(body).not_to match(/Available:.*\b#{Regexp.escape(table_name)}\b/)
    end

    it 'still lists non-excluded models and tables' do
      schema = tool_text(RailsAiBridge::Tools::GetSchema, detail: 'summary')
      models = tool_text(RailsAiBridge::Tools::GetModelDetails, detail: 'summary')
      expect(schema).to include('users')
      expect(models).to include('User')
    end
  end

  describe ':regulated preset' do
    before do
      config.preset = :regulated
      RailsAiBridge::ContextProvider.reset!
    end

    it 'does not leak schema or model names via MCP tools' do
      expect_no_domain_metadata_leak(domain_metadata_tool_bodies)
    end

    it 'does not leak schema or model names via rails:// resources' do
      uris = MCPExclusionParityTables::DOMAIN_METADATA_RESOURCE_URIS
      expect_no_domain_metadata_leak(uris.map { |uri| resource_body(uri) })
    end
  end

  describe 'disabled_introspection_categories :domain_metadata' do
    before do
      config.preset = :standard
      config.disabled_introspection_categories += [:domain_metadata]
      RailsAiBridge::ContextProvider.reset!
    end

    it 'does not leak schema or model names via MCP tools' do
      expect_no_domain_metadata_leak(domain_metadata_tool_bodies)
    end

    it 'does not leak schema or model names via rails:// resources' do
      uris = MCPExclusionParityTables::DOMAIN_METADATA_RESOURCE_URIS
      expect_no_domain_metadata_leak(uris.map { |uri| resource_body(uri) })
    end
  end

  describe 'regulated fixture without domain metadata' do
    let(:fixture) { RealFixtureAppContext.build_without_domain_metadata(:regulated_no_domain) }

    before do
      allow(RailsAiBridge::ContextProvider).to receive(:fetch_section) do |section, *_args|
        fixture[section]
      end
      allow(RailsAiBridge::ContextProvider).to receive(:fetch).and_return(fixture)
    end

    it 'does not leak fixture schema or model names via MCP tools' do
      expect_no_regulated_fixture_leak(domain_metadata_tool_bodies)
    end

    it 'does not leak fixture schema or model names via rails:// resources' do
      uris = MCPExclusionParityTables::DOMAIN_METADATA_RESOURCE_URIS
      expect_no_regulated_fixture_leak(uris.map { |uri| resource_body(uri) })
    end
  end

  def listing_tools
    policy = MCPExclusionParityTables::TOOL_EXCLUSION_POLICY
    RailsAiBridge::Server::TOOLS.select { |tool| policy[tool.tool_name] == :omits_excluded_names }
  end

  def listing_resource_uris
    MCPExclusionParityTables::STATIC_RESOURCE_POLICY.select { |_, policy| policy == :omits_excluded_names }.keys
  end

  def invoke_tool(tool_class)
    case tool_class.tool_name
    when 'rails_get_schema'
      [
        tool_text(tool_class, detail: 'summary'),
        tool_text(tool_class, detail: 'standard'),
        tool_text(tool_class, detail: 'full'),
        tool_text(tool_class, format: 'json', detail: 'full')
      ]
    when 'rails_get_model_details'
      [
        tool_text(tool_class, detail: 'summary'),
        tool_text(tool_class, detail: 'standard'),
        tool_text(tool_class, detail: 'full'),
        tool_text(tool_class, format: 'json')
      ]
    when 'rails_get_routes', 'rails_get_controllers'
      [
        tool_text(tool_class, detail: 'summary'),
        tool_text(tool_class, detail: 'full')
      ]
    else
      [tool_text(tool_class)]
    end
  end

  def domain_metadata_tool_bodies
    names = MCPExclusionParityTables::DOMAIN_METADATA_TOOL_NAMES
    listing_tools.select { |tool| names.include?(tool.tool_name) }
                 .flat_map { |tool_class| invoke_tool(tool_class) }
  end

  def tool_text(tool_class, **)
    tool_class.call(**).content.first[:text].to_s
  end

  def resource_body(uri)
    payload = RailsAiBridge::Resources.send(:resolve_resource_payload, uri)
    payload.is_a?(String) ? payload : payload.to_json
  end

  def expect_no_domain_metadata_leak(bodies)
    bodies.each do |body|
      MCPExclusionParityTables::DOMAIN_METADATA_NAMES.each do |name|
        expect(body).not_to include(name), "leaked #{name.inspect} in: #{body[0, 240]}"
      end
    end
  end

  def expect_no_regulated_fixture_leak(bodies)
    bodies.each do |body|
      MCPExclusionParityTables::REGULATED_FIXTURE_NAMES.each do |name|
        expect(body).not_to include(name), "leaked #{name.inspect} in: #{body[0, 240]}"
      end
    end
  end
end
