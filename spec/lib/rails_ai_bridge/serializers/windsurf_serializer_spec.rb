# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Serializers::WindsurfSerializer do
  it "never exceeds 6000 characters even with 200 models" do
    models = 200.times.each_with_object({}) { |i, h|
      h["Model#{i}"] = { associations: [], validations: [], table_name: "t#{i}" }
    }
    context = {
      app_name: "BigApp", rails_version: "8.0", ruby_version: "3.4",
      schema: { adapter: "postgresql", total_tables: 180 },
      models: models, routes: { total_routes: 1500 },
      gems: { notable: [ { name: "devise", category: :auth } ] },
      conventions: { architecture: [ "MVC" ] }
    }

    output = described_class.new(context).call
    expect(output.length).to be <= 6000
  end

  it "includes app name and stack info" do
    context = {
      app_name: "MyApp", rails_version: "8.0", ruby_version: "3.4",
      schema: { adapter: "postgresql", total_tables: 10 },
      models: { "User" => { associations: [] } },
      routes: { total_routes: 50 },
      gems: {}, conventions: {}
    }

    output = described_class.new(context).call
    expect(output).to include("MyApp")
    expect(output).to include("Rails 8.0")
    expect(output).to include("MCP Tools")
  end

  it "includes model names" do
    context = {
      app_name: "App", rails_version: "8.0", ruby_version: "3.4",
      schema: {}, models: { "User" => { associations: [] }, "Post" => { associations: [] } },
      routes: {}, gems: {}, conventions: {}
    }

    output = described_class.new(context).call
    expect(output).to include("User")
    expect(output).to include("Post")
  end
end
