# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::AssistantFormatsPreference do
  describe ".formats_for_default_bridge_task" do
    it "returns nil when install.yml is missing" do
      allow(described_class).to receive(:config_path).and_return(Pathname.new("/__no_such__/install.yml"))
      expect(described_class.formats_for_default_bridge_task).to be_nil
    end

    it "returns nil when YAML is not a Hash" do
      Dir.mktmpdir do |dir|
        path = Pathname.new(dir).join("config/rails_ai_bridge/install.yml")
        path.dirname.mkpath
        File.write(path, "--- []\n")
        allow(described_class).to receive(:config_path).and_return(path)
        expect(described_class.formats_for_default_bridge_task).to be_nil
      end
    end

    it "returns nil when formats list is empty after filtering" do
      Dir.mktmpdir do |dir|
        path = Pathname.new(dir).join("config/rails_ai_bridge/install.yml")
        path.dirname.mkpath
        File.write(path, YAML.dump({ "formats" => %w[unknown_fmt] }))
        allow(described_class).to receive(:config_path).and_return(path)
        expect(described_class.formats_for_default_bridge_task).to be_nil
      end
    end

    it "returns nil for invalid YAML" do
      Dir.mktmpdir do |dir|
        path = Pathname.new(dir).join("config/rails_ai_bridge/install.yml")
        path.dirname.mkpath
        File.write(path, "{ not: valid: yaml :")
        allow(described_class).to receive(:config_path).and_return(path)
        expect(described_class.formats_for_default_bridge_task).to be_nil
      end
    end
  end

  describe ".write!" do
    it "persists normalized format keys" do
      Dir.mktmpdir do |dir|
        path = Pathname.new(dir).join("config/rails_ai_bridge/install.yml")
        allow(described_class).to receive(:config_path).and_return(path)
        described_class.write!(formats: %i[cursor claude json])
        data = YAML.load_file(path)
        expect(data["formats"]).to eq(%w[cursor claude json])
      end
    end

    it "raises when Rails app path is unavailable" do
      allow(described_class).to receive(:config_path).and_return(nil)
      expect { described_class.write!(formats: [ :claude ]) }.to raise_error(RailsAiBridge::Error, /Rails app not available/)
    end
  end
end
