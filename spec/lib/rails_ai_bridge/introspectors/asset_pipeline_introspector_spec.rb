# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::AssetPipelineIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it "returns pipeline as 'none' when no Gemfile.lock" do
      expect(result[:pipeline]).to eq('none')
    end

    it 'returns empty importmap pins when no importmap.rb exists' do
      expect(result[:importmap_pins]).to eq([])
    end

    it 'returns manifest files as array' do
      expect(result[:manifest_files]).to be_an(Array)
    end

    it 'returns css_framework' do
      expect(result).to have_key(:css_framework)
    end

    it 'returns js_bundler' do
      expect(result).to have_key(:js_bundler)
    end

    context 'with an importmap.rb' do
      let(:importmap_path) { Rails.root.join('config/importmap.rb').to_s }

      before do
        File.write(importmap_path, <<~RUBY)
          pin "application"
          pin "@hotwired/turbo-rails", to: "turbo.min.js"
          pin "@hotwired/stimulus", to: "stimulus.min.js"
        RUBY
      end

      after { FileUtils.rm_f(importmap_path) }

      it 'extracts importmap pins' do
        expect(result[:importmap_pins]).to contain_exactly(
          '@hotwired/stimulus', '@hotwired/turbo-rails', 'application'
        )
      end

      it 'detects importmap as js_bundler' do
        expect(result[:js_bundler]).to eq('importmap')
      end

      it 'includes importmap.rb in manifest files' do
        expect(result[:manifest_files]).to include('importmap.rb')
      end
    end

    context 'with a vite.config.ts file' do
      let(:vite_config) { Rails.root.join('vite.config.ts').to_s }

      before { File.write(vite_config, 'export default {}') }
      after { FileUtils.rm_f(vite_config) }

      it 'detects vite as js_bundler' do
        expect(result[:js_bundler]).to eq('vite')
      end
    end
  end
end
