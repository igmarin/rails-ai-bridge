# frozen_string_literal: true

require "spec_helper"
require "rails_ai_bridge/services/app_introspection_service"
require "rails_ai_bridge/introspector"

RSpec.describe RailsAiBridge::AppIntrospectionService do
  let(:app) { double("Rails App") }
  let(:introspector_class) { RailsAiBridge::Introspector }
  let(:introspector_instance) { instance_double(RailsAiBridge::Introspector) }

  describe ".call" do
    it "creates introspector and calls it with app" do
      expect(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      expect(introspector_instance).to receive(:call).with(only: nil).and_return({test: "data"})
      
      result = described_class.call(app)
      
      expect(result).to be_a(RailsAiBridge::Service::Result)
      expect(result.success?).to be(true)
      expect(result.data).to eq({test: "data"})
    end

    it "passes only parameter to introspector" do
      expect(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      expect(introspector_instance).to receive(:call).with(only: [:models, :routes]).and_return({})
      
      result = described_class.call(app, only: [:models, :routes])
      expect(result.success?).to be(true)
    end

    it "handles introspector errors gracefully" do
      expect(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      expect(introspector_instance).to receive(:call).and_raise("Introspection failed")
      
      result = described_class.call(app)
      
      expect(result.failure?).to be(true)
      expect(result.errors).to eq(["Introspection failed"])
    end
  end

  describe "#call" do
    subject { described_class.new(app) }

    it "delegates to introspector with default class" do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).with(only: [:models]).and_return({models: []})
      
      result = subject.call(only: [:models])
      
      expect(result.success?).to be(true)
      expect(result.data).to eq({models: []})
    end

    it "allows custom introspector class" do
      custom_introspector = double("CustomIntrospector")
      allow(custom_introspector).to receive(:new).with(app).and_return(custom_introspector)
      allow(custom_introspector).to receive(:call).with(only: nil).and_return({custom: true})
      
      service = described_class.new(app, introspector_class: custom_introspector)
      result = service.call
      
      expect(result.data).to eq({custom: true})
    end
  end

  describe "result format" do
    it "returns Service::Result with proper structure" do
      allow(introspector_class).to receive(:new).with(app).and_return(introspector_instance)
      allow(introspector_instance).to receive(:call).and_return({
        models: ["User"],
        routes: {}
      })
      
      result = described_class.call(app)
      
      expect(result).to be_a(RailsAiBridge::Service::Result)
      expect(result.success?).to be(true)
      expect(result.data[:models]).to eq(["User"])
      expect(result.data[:routes]).to eq({})
      expect(result.errors).to be_empty
    end
  end
end
