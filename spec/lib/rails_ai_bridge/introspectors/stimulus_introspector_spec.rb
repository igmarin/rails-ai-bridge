# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::StimulusIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    context 'when no Stimulus controllers directory exists' do
      it 'returns empty controllers array' do
        result = introspector.call
        expect(result[:controllers]).to eq([])
      end
    end

    context 'with Stimulus controllers' do
      let(:controllers_dir) { Rails.root.join('app/javascript/controllers').to_s }

      before do
        FileUtils.mkdir_p(controllers_dir)
        File.write(File.join(controllers_dir, 'hello_controller.js'), <<~JS)
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
        FileUtils.rm_f(File.join(controllers_dir, 'hello_controller.js'))
        FileUtils.rmdir(controllers_dir) if File.directory?(controllers_dir) && Dir.empty?(controllers_dir)
      end

      it 'discovers controllers' do
        result = introspector.call
        expect(result[:controllers].size).to eq(1)
        expect(result[:controllers].first[:name]).to eq('hello')
        expect(result[:controllers].first[:file]).to eq('hello_controller.js')
      end

      it 'extracts targets' do
        result = introspector.call
        expect(result[:controllers].first[:targets]).to contain_exactly('name', 'output')
      end

      it 'extracts values with types' do
        result = introspector.call
        expect(result[:controllers].first[:values]).to eq('greeting' => 'String', 'count' => 'Number')
      end

      it 'extracts actions' do
        result = introspector.call
        expect(result[:controllers].first[:actions]).to include('greet', 'reset')
      end

      it 'extracts outlets' do
        result = introspector.call
        expect(result[:controllers].first[:outlets]).to contain_exactly('search', 'results')
      end

      it 'extracts classes' do
        result = introspector.call
        expect(result[:controllers].first[:classes]).to contain_exactly('active', 'loading')
      end
    end

    context 'with a controller containing async methods and control flow' do
      let(:controllers_dir) { Rails.root.join('app/javascript/controllers').to_s }

      before do
        FileUtils.mkdir_p(controllers_dir)
        File.write(File.join(controllers_dir, 'search_controller.js'), <<~JS)
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
        FileUtils.rm_f(File.join(controllers_dir, 'search_controller.js'))
        FileUtils.rmdir(controllers_dir) if File.directory?(controllers_dir) && Dir.empty?(controllers_dir)
      end

      it 'extracts async methods as actions' do
        result = introspector.call
        actions = result[:controllers].first[:actions]
        expect(actions).to include('search', 'render')
      end

      it 'does not include control flow keywords' do
        result = introspector.call
        actions = result[:controllers].first[:actions]
        expect(actions).not_to include('if', 'for', 'while')
      end
    end

    context 'when a controller file raises an error during parsing' do
      let(:controllers_dir) { Rails.root.join('app/javascript/controllers').to_s }
      let(:bad_file) { File.join(controllers_dir, 'broken_controller.js') }

      before do
        FileUtils.mkdir_p(controllers_dir)
        File.write(bad_file, 'valid content')
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(bad_file).and_raise(StandardError, 'read error')
      end

      after do
        FileUtils.rm_f(bad_file)
        FileUtils.rmdir(controllers_dir) if File.directory?(controllers_dir) && Dir.empty?(controllers_dir)
      end

      it 'returns an error entry for the broken controller' do
        result = introspector.call
        controller = result[:controllers].first
        expect(controller[:name]).to eq('broken_controller.js')
        expect(controller[:error]).to eq('read error')
      end
    end

    context 'when a controller has no static targets/values/outlets/classes' do
      let(:controllers_dir) { Rails.root.join('app/javascript/controllers').to_s }

      before do
        FileUtils.mkdir_p(controllers_dir)
        File.write(File.join(controllers_dir, 'minimal_controller.js'), <<~JS)
          import { Controller } from "@hotwired/stimulus"

          export default class extends Controller {
            connect() {
              console.log("connected")
            }
          }
        JS
      end

      after do
        FileUtils.rm_f(File.join(controllers_dir, 'minimal_controller.js'))
        FileUtils.rmdir(controllers_dir) if File.directory?(controllers_dir) && Dir.empty?(controllers_dir)
      end

      it 'returns empty arrays and hashes for missing static declarations' do
        result = introspector.call
        controller = result[:controllers].first
        expect(controller[:targets]).to eq([])
        expect(controller[:values]).to eq({})
        expect(controller[:outlets]).to eq([])
        expect(controller[:classes]).to eq([])
      end

      it 'does not include connect as an action' do
        result = introspector.call
        expect(result[:controllers].first[:actions]).not_to include('connect')
      end
    end

    context 'when the glob raises an error' do
      it 'returns an error hash' do
        bad_resolver = double('PathResolver')
        allow(bad_resolver).to receive(:glob_for).and_raise(StandardError, 'glob failure')
        introspector = described_class.new(Rails.application)
        introspector.instance_variable_set(:@path_resolver, bad_resolver)
        result = introspector.call
        expect(result[:error]).to eq('glob failure')
      end
    end

    context 'with a TypeScript controller' do
      let(:controllers_dir) { Rails.root.join('app/javascript/controllers').to_s }

      before do
        FileUtils.mkdir_p(controllers_dir)
        File.write(File.join(controllers_dir, 'ts_controller.ts'), <<~TS)
          import { Controller } from "@hotwired/stimulus"

          export default class extends Controller {
            static targets = ["input"]
            static values = { name: String }

            submit() {
              this.inputTarget.value = ""
            }
          }
        TS
      end

      after do
        FileUtils.rm_f(File.join(controllers_dir, 'ts_controller.ts'))
        FileUtils.rmdir(controllers_dir) if File.directory?(controllers_dir) && Dir.empty?(controllers_dir)
      end

      it 'discovers and parses TypeScript controllers' do
        result = introspector.call
        controller = result[:controllers].first
        expect(controller[:name]).to eq('ts')
        expect(controller[:file]).to eq('ts_controller.ts')
        expect(controller[:targets]).to eq(['input'])
        expect(controller[:values]).to eq('name' => 'String')
        expect(controller[:actions]).to include('submit')
      end
    end
  end
end
