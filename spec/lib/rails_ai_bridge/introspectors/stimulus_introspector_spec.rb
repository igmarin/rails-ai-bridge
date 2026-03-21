# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::StimulusIntrospector do
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
            static outlets = ["search", "results"]
            static classes = ["active", "loading"]

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
        expect(result[:controllers].first[:file]).to eq("hello_controller.js")
      end

      it "extracts targets" do
        result = introspector.call
        expect(result[:controllers].first[:targets]).to contain_exactly("name", "output")
      end

      it "extracts values with types" do
        result = introspector.call
        expect(result[:controllers].first[:values]).to eq("greeting" => "String", "count" => "Number")
      end

      it "extracts actions" do
        result = introspector.call
        expect(result[:controllers].first[:actions]).to include("greet", "reset")
      end

      it "extracts outlets" do
        result = introspector.call
        expect(result[:controllers].first[:outlets]).to contain_exactly("search", "results")
      end

      it "extracts classes" do
        result = introspector.call
        expect(result[:controllers].first[:classes]).to contain_exactly("active", "loading")
      end
    end

    context "with a controller containing async methods and control flow" do
      let(:controllers_dir) { File.join(Rails.root, "app/javascript/controllers") }

      before do
        FileUtils.mkdir_p(controllers_dir)
        File.write(File.join(controllers_dir, "search_controller.js"), <<~JS)
          import { Controller } from "@hotwired/stimulus"

          export default class extends Controller {
            static targets = ["query"]

            async search() {
              const response = await fetch("/search")
              if (response.ok) {
                this.render(await response.json())
              }
            }

            render(data) {
              this.queryTarget.value = data.query
            }
          }
        JS
      end

      after do
        FileUtils.rm_rf(File.join(Rails.root, "app/javascript"))
      end

      it "extracts async methods as actions" do
        result = introspector.call
        actions = result[:controllers].first[:actions]
        expect(actions).to include("search", "render")
      end

      it "does not include control flow keywords" do
        result = introspector.call
        actions = result[:controllers].first[:actions]
        expect(actions).not_to include("if", "for", "while")
      end
    end
  end
end
