# frozen_string_literal: true

require "spec_helper"
require "rails_ai_bridge/services/context_generation_service"
require "rails_ai_bridge/serializers/context_file_serializer"

RSpec.describe RailsAiBridge::ContextGenerationService do
  let(:context_data) { { models: [ "User" ], routes: {} } }
  let(:serializer_class) { RailsAiBridge::Serializers::ContextFileSerializer }
  let(:serializer_instance) { instance_double(serializer_class) }

  describe ".call" do
    it "generates context files with default serializer" do
      expect(serializer_class).to receive(:new).with(context_data, format: :all).and_return(serializer_instance)
      expect(serializer_instance).to receive(:call).and_return({
        written: [ "/tmp/CLAUDE.md" ],
        skipped: []
      })

      result = described_class.call(context_data)

      expect(result.success?).to be(true)
      expect(result.data[:written]).to eq([ "/tmp/CLAUDE.md" ])
      expect(result.data[:skipped]).to eq([])
    end

    it "accepts custom format parameter" do
      expect(serializer_class).to receive(:new).with(context_data, format: :claude).and_return(serializer_instance)
      expect(serializer_instance).to receive(:call).and_return({ written: [], skipped: [] })

      result = described_class.call(context_data, format: :claude)
      expect(result.success?).to be(true)
    end

    it "handles serializer errors gracefully" do
      expect(serializer_class).to receive(:new).and_return(serializer_instance)
      expect(serializer_instance).to receive(:call).and_raise("Serialization failed")

      result = described_class.call(context_data)

      expect(result.failure?).to be(true)
      expect(result.errors).to eq([ "Serialization failed" ])
    end
  end

  describe "#call" do
    subject { described_class.new(context_data) }

    it "uses default format when not specified" do
      expect(serializer_class).to receive(:new).with(context_data, format: :all).and_return(serializer_instance)
      allow(serializer_instance).to receive(:call).and_return({ written: [ "file1.md" ], skipped: [ "file2.md" ] })

      result = subject.call

      expect(result.data[:written]).to eq([ "file1.md" ])
      expect(result.data[:skipped]).to eq([ "file2.md" ])
    end

    it "allows custom serializer class" do
      custom_serializer = double("CustomSerializer")
      allow(custom_serializer).to receive(:new).with(context_data, format: :json).and_return(custom_serializer)
      allow(custom_serializer).to receive(:call).and_return({ written: [ "output.json" ] })

      service = described_class.new(context_data, serializer_class: custom_serializer, format: :json)
      result = service.call

      expect(result.data[:written]).to eq([ "output.json" ])
    end
  end

  describe "result structure" do
    it "returns Service::Result with written and skipped files" do
      allow(serializer_class).to receive(:new).with(context_data, format: :all).and_return(serializer_instance)
      allow(serializer_instance).to receive(:call).and_return({
        written: [ "/tmp/CLAUDE.md", "/tmp/.cursorrules" ],
        skipped: [ "/tmp/CODEX.md" ]
      })

      result = described_class.call(context_data)

      expect(result).to be_a(RailsAiBridge::Service::Result)
      expect(result.success?).to be(true)
      expect(result.data[:written].count).to eq(2)
      expect(result.data[:skipped].count).to eq(1)
    end
  end

  describe "error handling" do
    it "captures StandardError exceptions" do
      allow(serializer_class).to receive(:new).and_raise(ArgumentError, "Invalid format")

      result = described_class.call(context_data, format: :invalid)

      expect(result.failure?).to be(true)
      expect(result.errors).to eq([ "Invalid format" ])
    end
  end
end
