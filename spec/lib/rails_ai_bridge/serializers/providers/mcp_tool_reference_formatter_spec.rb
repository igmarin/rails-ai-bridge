# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::Providers::McpToolReferenceFormatter do
  subject(:formatter) { described_class.new(context: {}) }

  describe "#call" do
    it "returns a markdown string" do
      expect(formatter.call).to be_a(String)
      expect(formatter.call).to include("## MCP Tool Reference")
    end

    it "includes details for rails_get_schema" do
      expect(formatter.call).to include("### rails_get_schema")
      expect(formatter.call).to include('- `rails_get_schema(detail:"summary")`')
    end

    it "includes details for rails_get_model_details" do
      expect(formatter.call).to include("### rails_get_model_details")
      expect(formatter.call).to include('- `rails_get_model_details(model:"User")`')
    end

    it "includes details for rails_get_routes" do
      expect(formatter.call).to include("### rails_get_routes")
      expect(formatter.call).to include('- `rails_get_routes(controller:"users")`')
    end

    it "includes details for rails_get_controllers" do
      expect(formatter.call).to include("### rails_get_controllers")
      expect(formatter.call).to include('- `rails_get_controllers(controller:"UsersController")`')
    end

    it "includes details for other tools" do
      expect(formatter.call).to include("### Other tools")
      expect(formatter.call).to include("- `rails_get_config`")
      expect(formatter.call).to include('- `rails_search_code(pattern:"regex", file_type:"rb", max_results:20)`')
    end

    it "uses literal newline characters for formatting" do
      expect(formatter.call).to include("\n")
    end
  end
end
