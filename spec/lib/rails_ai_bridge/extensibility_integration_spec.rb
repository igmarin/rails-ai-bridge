# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RailsAiBridge extensibility integration" do
  let(:custom_introspector) do
    Class.new do
      def initialize(_app); end

      def call
        {
          enabled: true,
          items: [ "alpha", "beta" ]
        }
      end
    end
  end

  let(:custom_tool) do
    Class.new(RailsAiBridge::Tools::BaseTool) do
      tool_name "rails_get_custom_context"
      description "Returns custom extension context for integration testing."
      input_schema(properties: {})

      def self.call(server_context: nil)
        data = cached_section(:custom)
        text_response(data[:items].join(", "))
      end
    end
  end

  around do |example|
    original_introspectors = RailsAiBridge.configuration.introspectors.dup
    original_additional_introspectors = RailsAiBridge.configuration.additional_introspectors.dup
    original_additional_tools = RailsAiBridge.configuration.additional_tools.dup
    original_additional_resources = RailsAiBridge.configuration.additional_resources.dup
    RailsAiBridge::ContextProvider.reset!
    example.run
  ensure
    RailsAiBridge.configuration.introspectors = original_introspectors
    RailsAiBridge.configuration.additional_introspectors = original_additional_introspectors
    RailsAiBridge.configuration.additional_tools = original_additional_tools
    RailsAiBridge.configuration.additional_resources = original_additional_resources
    RailsAiBridge::ContextProvider.reset!
  end

  it "supports a custom introspector, tool, and resource working together" do
    RailsAiBridge.configuration.additional_introspectors[:custom] = custom_introspector
    RailsAiBridge.configuration.additional_tools << custom_tool
    RailsAiBridge.configuration.additional_resources["rails://custom"] = {
      name: "Custom",
      description: "Custom extension resource",
      mime_type: "application/json",
      key: :custom
    }

    server = RailsAiBridge::Server.new(Rails.application).build
    tool_response = custom_tool.call
    resource_rows = RailsAiBridge::Resources.send(:handle_read, { uri: "rails://custom" })
    resource_json = JSON.parse(resource_rows.first[:text])

    expect(server.tools).to have_key("rails_get_custom_context")
    expect(server.resources.map(&:uri)).to include("rails://custom")
    expect(tool_response.content.first[:text]).to include("alpha, beta")
    expect(resource_json).to eq({ "enabled" => true, "items" => [ "alpha", "beta" ] })
  end
end
