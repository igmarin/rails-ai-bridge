# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiContext::Introspectors::StimulusIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    context "when no Stimulus controllers directory exists" do
      it "returns empty controllers array" do
        result = introspector.call
        expect(result[:controllers]).to eq([])
      end
    end

    context "with Stimulus controllers" do
      let(:controllers_dir) { File.join(Rails.root, "app/javascript/controllers") }

      before do
        FileUtils.mkdir_p(controllers_dir)
        File.write(File.join(controllers_dir, "hello_controller.js"), <<~JS)
          import { Controller } from "@hotwired/stimulus"

          export default class extends Controller {
            static targets = ["name", "output"]
            static values = { greeting: String, count: Number }

            greet() {
              this.outputTarget.textContent = `${this.greetingValue}, ${this.nameTarget.value}!`
            }

            reset() {
              this.nameTarget.value = ""
            }
          }
        JS
      end

      after do
        FileUtils.rm_rf(File.join(Rails.root, "app/javascript"))
      end

      it "discovers controllers" do
        result = introspector.call
        expect(result[:controllers].size).to eq(1)
        expect(result[:controllers].first[:name]).to eq("hello")
      end

      it "extracts targets" do
        result = introspector.call
        expect(result[:controllers].first[:targets]).to contain_exactly("name", "output")
      end

      it "extracts values" do
        result = introspector.call
        expect(result[:controllers].first[:values]).to include("greeting" => "String")
      end

      it "extracts actions" do
        result = introspector.call
        expect(result[:controllers].first[:actions]).to include("greet", "reset")
      end
    end
  end
end
