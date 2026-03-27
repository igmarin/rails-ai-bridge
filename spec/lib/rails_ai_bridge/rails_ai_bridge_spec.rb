# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge do
  describe ".resolve_generate_format" do
    it "returns :all when install.yml selection is absent" do
      allow(RailsAiBridge::AssistantFormatsPreference).to receive(:formats_for_default_bridge_task).and_return(nil)
      expect(described_class.resolve_generate_format(:install)).to eq(:all)
    end

    it "returns normalized list when install.yml defines formats" do
      allow(RailsAiBridge::AssistantFormatsPreference).to receive(:formats_for_default_bridge_task)
        .and_return(%i[claude json])
      expect(described_class.resolve_generate_format(:install)).to eq(%i[claude json])
    end

    it "passes through non-install format symbols" do
      expect(described_class.resolve_generate_format(:codex)).to eq(:codex)
    end
  end

  describe ".generate_context" do
    it "warns when assistant overrides are still the install stub" do
      allow(RailsAiBridge::Serializers::SharedAssistantGuidance).to receive(:overrides_stub_active?).and_return(true)

      ctx = { app_name: "T" }
      allow(described_class).to receive(:introspect).and_return(ctx)
      serializer = instance_double(RailsAiBridge::Serializers::ContextFileSerializer, call: { written: [], skipped: [] })
      allow(RailsAiBridge::Serializers::ContextFileSerializer).to receive(:new).with(ctx, format: :claude).and_return(serializer)

      expect do
        described_class.generate_context(format: :claude)
      end.to output(/omit-merge/).to_stderr
    end
  end
end
