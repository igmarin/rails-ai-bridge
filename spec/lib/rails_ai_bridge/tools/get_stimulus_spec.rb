# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetStimulus do
  let(:stimulus_data) do
    {
      controllers: [
        {
          name: "clipboard",
          file: "app/javascript/controllers/clipboard_controller.js",
          targets: [ "input" ],
          values: { content: "string" },
          actions: [ "copy" ],
          outlets: [],
          classes: []
        },
        {
          name: "admin--filters",
          file: "app/javascript/controllers/admin/filters_controller.js",
          targets: [ "query", "status" ],
          values: { enabled: "boolean" },
          actions: [ "apply", "clear" ],
          outlets: [ "search-results" ],
          classes: [ "selected" ]
        }
      ]
    }
  end

  before do
    allow(described_class).to receive(:cached_section).with(:stimulus).and_return(stimulus_data)
  end

  let(:response) { described_class.call(**params) }
  let(:content) { response.content.first[:text] }

  describe ".call" do
    context "with no controller specified (listing all)" do
      context "with detail: 'summary'" do
        let(:params) { { detail: "summary" } }

        it "returns a summary of controllers" do
          expect(content).to include("# Stimulus Controllers (2)")
          expect(content).to include("- **admin--filters** — 2 targets, 2 actions")
          expect(content).to include("- **clipboard** — 1 targets, 1 actions")
        end
      end

      context "with detail: 'standard' (default)" do
        let(:params) { {} }

        it "returns a standard list of controllers" do
          expect(content).to include("# Stimulus Controllers (2)")
          expect(content).to include("## admin--filters")
          expect(content).to include("- Targets: query, status")
          expect(content).to include("- Actions: apply, clear")
          expect(content).to include("- Values: enabled")
          expect(content).to include("## clipboard")
        end
      end

      context "with detail: 'full'" do
        let(:params) { { detail: "full" } }

        it "returns a detailed list of controllers" do
          expect(content).to include("# Stimulus Controllers (2)")
          expect(content).to include("## admin--filters")
          expect(content).to include("- File: app/javascript/controllers/admin/filters_controller.js")
          expect(content).to include("- Outlets: search-results")
          expect(content).to include("- Classes: selected")
          expect(content).to include("- Values: enabled: boolean")
        end
      end
    end

    context "when a specific controller is requested" do
      let(:params) { { controller: "clipboard" } }

      it "returns full details for that controller" do
        expect(content).to include("# clipboard")
        expect(content).to include("- File: app/javascript/controllers/clipboard_controller.js")
        expect(content).to include("## Targets")
        expect(content).to include("- `input`")
        expect(content).to include("## Values")
        expect(content).to include("- `content`: string")
        expect(content).to include("## Actions")
        expect(content).to include("- `copy`")
      end
    end

    context "when the controller is not found" do
      let(:params) { { controller: "nonexistent" } }

      it "returns a helpful message" do
        expect(content).to include("Stimulus controller 'nonexistent' not found.")
      end
    end

    context "when Stimulus introspection is not available" do
      let(:stimulus_data) { nil }
      let(:params) { {} }

      it "returns an informative message" do
        expect(content).to include("Stimulus introspection not available.")
      end
    end

    context "when Stimulus introspection has an error" do
      let(:stimulus_data) { { error: "Something went wrong" } }
      let(:params) { {} }

      it "returns the error message" do
        expect(content).to include("Stimulus introspection failed: Something went wrong")
      end
    end
  end
end
