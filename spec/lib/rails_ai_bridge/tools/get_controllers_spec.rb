# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetControllers do
  let(:controllers_data) do
    {
      controllers: {
        "PostsController" => {
          parent_class: "ApplicationController",
          api_controller: false,
          actions: [ "index", "show", "create" ],
          filters: [ { kind: "before_action", name: "set_post", only: [ "show" ] } ],
          strong_params: [ "post_params" ]
        },
        "Api::V1::UsersController" => {
          parent_class: "Api::V1::BaseController",
          api_controller: true,
          actions: [ "index", "show" ],
          filters: [],
          strong_params: []
        }
      }
    }
  end

  before do
    allow(described_class).to receive(:cached_section).with(:controllers).and_return(controllers_data)
  end

  let(:response) { described_class.call(**params) }
  let(:content) { response.content.first[:text] }

  describe ".call" do
    context "when requesting a specific controller" do
      let(:params) { { controller: "PostsController" } }

      it "returns full details for that controller" do
        expect(content).to include("# PostsController")
        expect(content).to include("**Parent:** `ApplicationController`")
        expect(content).to include("## Actions")
        expect(content).to include("- `create`")
        expect(content).to include("## Filters")
        expect(content).to include("- `before_action` **set_post** (only: show)")
        expect(content).to include("## Strong Params")
        expect(content).to include("- `post_params`")
      end
    end

    context "with detail: 'summary'" do
      let(:params) { { detail: "summary" } }

      it "returns a summary of controllers and action counts" do
        expect(content).to include("# Controllers (2)")
        expect(content).to include("- **Api::V1::UsersController** — 2 actions")
        expect(content).to include("- **PostsController** — 3 actions")
      end
    end

    context "with detail: 'standard' (default)" do
      let(:params) { {} }

      it "returns a list of controllers and their actions" do
        expect(content).to include("# Controllers (2)")
        expect(content).to include("- **Api::V1::UsersController** — index, show")
        expect(content).to include("- **PostsController** — index, show, create")
      end
    end

    context "with detail: 'full'" do
      let(:params) { { detail: "full" } }

      it "returns detailed info for all controllers" do
        expect(content).to include("## Api::V1::UsersController")
        expect(content).to include("- Actions: index, show")
        expect(content).to include("## PostsController")
        expect(content).to include("- Filters: before_action set_post")
        expect(content).to include("- Strong params: post_params")
      end
    end

    context "when controller is not found" do
      let(:params) { { controller: "MissingController" } }

      it "returns a helpful error message" do
        expect(content).to include("Controller 'MissingController' not found.")
        expect(content).to include("Available: Api::V1::UsersController, PostsController")
      end
    end
  end
end
