# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetGems do
  let(:gems_data) do
    {
      total_gems: 3,
      notable_gems: [
        { name: "devise", version: "4.8.1", category: "auth", note: "Authentication solution." },
        { name: "sidekiq", version: "6.5.7", category: "jobs", note: "Background job processing." },
        { name: "rspec-rails", version: "5.0.0", category: "testing", note: "Testing framework." }
      ]
    }
  end

  before do
    allow(described_class).to receive(:cached_section).with(:gems).and_return(gems_data)
  end

  let(:response) { described_class.call(**params) }
  let(:content) { response.content.first[:text] }

  describe ".call" do
    context "with no category specified (default: 'all')" do
      let(:params) { {} }

      it "returns all notable gems, grouped by category" do
        expect(content).to include("# Gem Analysis")
        expect(content).to include("Total gems: 3")
        expect(content).to include("## Auth")
        expect(content).to include("- **devise** (4.8.1): Authentication solution.")
        expect(content).to include("## Jobs")
        expect(content).to include("- **sidekiq** (6.5.7): Background job processing.")
        expect(content).to include("## Testing")
        expect(content).to include("- **rspec-rails** (5.0.0): Testing framework.")
      end
    end

    context "with a specific category" do
      let(:params) { { category: "auth" } }

      it "returns only gems from that category" do
        expect(content).to include("## Auth")
        expect(content).to include("- **devise** (4.8.1): Authentication solution.")
        expect(content).not_to include("sidekiq")
        expect(content).not_to include("rspec-rails")
      end
    end

    context "with a category that has no notable gems" do
      let(:params) { { category: "frontend" } }

      it "returns a message indicating no notable gems found" do
        expect(content).to include("_No notable gems found in category 'frontend'._")
      end
    end

    context "when gem introspection is not available" do
      let(:gems_data) { nil }
      let(:params) { {} }

      it "returns an informative message" do
        expect(content).to include("Gem introspection not available.")
      end
    end

    context "when gem introspection has an error" do
      let(:gems_data) { { error: "Something went wrong" } }
      let(:params) { {} }

      it "returns the error message" do
        expect(content).to include("Gem introspection failed: Something went wrong")
      end
    end
  end
end
