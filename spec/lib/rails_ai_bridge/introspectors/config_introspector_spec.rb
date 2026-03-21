# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::ConfigIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    subject(:result) { introspector.call }

    it "returns cache store as a known value" do
      expect(result[:cache_store]).to be_a(String)
      expect(result[:cache_store]).not_to be_empty
    end

    it "returns session store" do
      expect(result).to have_key(:session_store)
    end

    it "returns timezone as a non-empty string" do
      expect(result[:timezone]).to be_a(String)
      expect(result[:timezone]).not_to be_empty
    end

    it "returns middleware stack as non-empty array of strings" do
      expect(result[:middleware_stack]).to be_an(Array)
      expect(result[:middleware_stack]).not_to be_empty
      expect(result[:middleware_stack]).to all(be_a(String))
    end

    it "returns initializers as array of strings" do
      expect(result[:initializers]).to be_an(Array)
      result[:initializers].each do |init|
        expect(init).to be_a(String)
        expect(init).to end_with(".rb")
      end
    end

    it "returns credentials keys as array" do
      expect(result[:credentials_keys]).to be_an(Array)
    end

    it "returns current attributes as array" do
      expect(result[:current_attributes]).to be_an(Array)
    end

    it "does not return an error" do
      expect(result).not_to have_key(:error)
    end

    context "with a CurrentAttributes model" do
      let(:fixture_model) { File.join(Rails.root, "app/models/current.rb") }

      before do
        File.write(fixture_model, <<~RUBY)
          class Current < ActiveSupport::CurrentAttributes
            attribute :user
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it "detects CurrentAttributes classes" do
        expect(result[:current_attributes]).to include("Current")
      end
    end
  end
end
