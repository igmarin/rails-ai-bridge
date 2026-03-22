# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetStimulus do
  before { described_class.reset_cache! }

  describe "detail parameter" do
    before do
      allow(described_class).to receive(:cached_section).with(:stimulus).and_return({
        controllers: [
          {
            name: "admin--filters",
            file: "admin/filters_controller.js",
            targets: %w[form panel],
            values: { "open" => "Boolean" },
            actions: %w[toggle reset],
            outlets: [ "modal" ],
            classes: [ "active" ]
          },
          {
            name: "clipboard",
            file: "clipboard_controller.js",
            targets: [ "source" ],
            values: { "successMessage" => "String" },
            actions: [ "copy" ],
            outlets: [],
            classes: []
          }
        ]
      })
    end

    it "returns controller counts for detail:summary" do
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]

      expect(text).to include("Stimulus Controllers")
      expect(text).to include("**clipboard**")
      expect(text).to include("1 targets")
      expect(text).to include("1 actions")
    end

    it "returns controller details for detail:standard" do
      result = described_class.call(detail: "standard")
      text = result.content.first[:text]

      expect(text).to include("admin--filters")
      expect(text).to include("Targets: form, panel")
      expect(text).to include("Actions: toggle, reset")
    end

    it "returns full detail for detail:full" do
      result = described_class.call(detail: "full")
      text = result.content.first[:text]

      expect(text).to include("## clipboard")
      expect(text).to include("successMessage")
      expect(text).to include("clipboard_controller.js")
    end

    it "returns full detail for a specific controller" do
      result = described_class.call(controller: "admin--filters", detail: "summary")
      text = result.content.first[:text]

      expect(text).to include("# admin--filters")
      expect(text).to include("## Targets")
      expect(text).to include("## Actions")
    end

    it "supports case-insensitive controller lookup" do
      result = described_class.call(controller: "CLIPBOARD")
      text = result.content.first[:text]

      expect(text).to include("# clipboard")
    end

    it "handles missing stimulus data gracefully" do
      allow(described_class).to receive(:cached_section).with(:stimulus).and_return(nil)

      result = described_class.call(detail: "summary")
      text = result.content.first[:text]

      expect(text).to include("not available")
    end
  end
end
