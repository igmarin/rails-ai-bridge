# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Resources do
  describe "rails://config resource JSON" do
    around do |example|
      saved_introspectors = RailsAiBridge.configuration.introspectors.dup
      saved_expose = RailsAiBridge.configuration.expose_credentials_key_names
      RailsAiBridge.configuration.introspectors |= [ :config ]
      example.run
    ensure
      RailsAiBridge.configuration.introspectors = saved_introspectors
      RailsAiBridge.configuration.expose_credentials_key_names = saved_expose
    end

    it "does not include credentials_keys when expose_credentials_key_names is false" do
      RailsAiBridge.configuration.expose_credentials_key_names = false
      rows = described_class.send(:handle_read, { uri: "rails://config" })
      json = JSON.parse(rows.first[:text])
      expect(json).not_to have_key("credentials_keys")
    end
  end

  describe "additional resources" do
    around do |example|
      saved_resources = RailsAiBridge.configuration.additional_resources.dup
      example.run
    ensure
      RailsAiBridge.configuration.additional_resources = saved_resources
    end

    it "reads configured custom resources through the shared context provider" do
      RailsAiBridge.configuration.additional_resources["rails://custom"] = {
        name: "Custom",
        description: "Custom resource",
        mime_type: "application/json",
        key: :custom
      }
      allow(RailsAiBridge::ContextProvider).to receive(:fetch_section).with(:custom).and_return({ "value" => 7 })

      rows = described_class.send(:handle_read, { uri: "rails://custom" })
      json = JSON.parse(rows.first[:text])

      expect(json).to eq({ "value" => 7 })
      expect(RailsAiBridge::ContextProvider).to have_received(:fetch_section).with(:custom)
    end
  end
end
