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

  describe '#call with custom app root' do
    let(:app_root) { Pathname.new(Dir.mktmpdir('asset-pipeline')) }
    let(:custom_app) { double('Rails::Application', root: app_root) }
    let(:introspector) { described_class.new(custom_app) }
    let(:result) { introspector.call }

    after { FileUtils.rm_rf(app_root) }

    context 'with propshaft in Gemfile.lock' do
      before { File.write(app_root.join('Gemfile.lock'), "propshaft (0.9.0)\n") }

      it 'detects propshaft pipeline' do
        expect(result[:pipeline]).to eq('propshaft')
      end
    end

    context 'with sprockets in Gemfile.lock' do
      before { File.write(app_root.join('Gemfile.lock'), "sprockets (4.2.0)\n") }

      it 'detects sprockets pipeline' do
        expect(result[:pipeline]).to eq('sprockets')
      end
    end

    context 'with tailwindcss-rails in Gemfile.lock' do
      before { File.write(app_root.join('Gemfile.lock'), "tailwindcss-rails (2.0.0)\n") }

      it 'detects tailwindcss CSS framework' do
        expect(result[:css_framework]).to eq('tailwindcss')
      end
    end

    context 'with bootstrap in Gemfile.lock' do
      before { File.write(app_root.join('Gemfile.lock'), "bootstrap (5.0.0)\n") }

      it 'detects bootstrap CSS framework' do
        expect(result[:css_framework]).to eq('bootstrap')
      end
    end

    context 'with bootstrap in package.json' do
      before do
        File.write(app_root.join('Gemfile.lock'), "rails (7.1.0)\n")
        File.write(app_root.join('package.json'), '{"dependencies": {"bootstrap": "5.0"}}')
      end

      it 'detects bootstrap CSS framework from package.json' do
        expect(result[:css_framework]).to eq('bootstrap')
      end
    end

    context 'with bulma in package.json' do
      before do
        File.write(app_root.join('Gemfile.lock'), "rails (7.1.0)\n")
        File.write(app_root.join('package.json'), '{"dependencies": {"bulma": "0.9"}}')
      end

      it 'detects bulma CSS framework' do
        expect(result[:css_framework]).to eq('bulma')
      end
    end

    context 'with esbuild in package.json' do
      before do
        File.write(app_root.join('package.json'), '{"dependencies": {"esbuild": "0.15"}}')
      end

      it 'detects esbuild as js_bundler' do
        expect(result[:js_bundler]).to eq('esbuild')
      end
    end

    context 'with webpack config directory' do
      before { FileUtils.mkdir_p(app_root.join('config/webpack')) }

      it 'detects webpack as js_bundler' do
        expect(result[:js_bundler]).to eq('webpack')
      end
    end

    context 'with webpack in package.json' do
      before { File.write(app_root.join('package.json'), '{"dependencies": {"webpack": "5.0"}}') }

      it 'detects webpack as js_bundler from package.json' do
        expect(result[:js_bundler]).to eq('webpack')
      end
    end

    context 'with rollup in package.json' do
      before { File.write(app_root.join('package.json'), '{"dependencies": {"rollup": "3.0"}}') }

      it 'detects rollup as js_bundler' do
        expect(result[:js_bundler]).to eq('rollup')
      end
    end

    context 'with manifest.js and package.json' do
      before do
        FileUtils.mkdir_p(app_root.join('app/assets/config'))
        File.write(app_root.join('app/assets/config/manifest.js'), '// manifest')
        File.write(app_root.join('package.json'), '{}')
      end

      it 'includes manifest.js and package.json in manifest_files' do
        expect(result[:manifest_files]).to include('manifest.js', 'package.json')
      end
    end

    context 'with unreadable Gemfile.lock' do
      before do
        path = app_root.join('Gemfile.lock').to_s
        File.write(path, "propshaft (0.9.0)\n")
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(path).and_raise(StandardError, 'permission denied')
      end

      after { allow(File).to receive(:read).and_call_original }

      it 'returns none for pipeline on read error' do
        expect(result[:pipeline]).to eq('none')
      end
    end

    context 'with unreadable package.json' do
      before do
        File.write(app_root.join('Gemfile.lock'), "rails (7.1.0)\n")
        path = app_root.join('package.json').to_s
        File.write(path, '{"bulma": "0.9"}')
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(path).and_raise(StandardError, 'permission denied')
      end

      after { allow(File).to receive(:read).and_call_original }

      it 'returns nil for css_framework on read error' do
        expect(result[:css_framework]).to be_nil
      end
    end

    context 'with unreadable importmap.rb' do
      before do
        path = app_root.join('config/importmap.rb').to_s
        FileUtils.mkdir_p(app_root.join('config'))
        File.write(path, 'pin "application"')
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(path).and_raise(StandardError, 'permission denied')
      end

      after { allow(File).to receive(:read).and_call_original }

      it 'returns empty array for importmap_pins on read error' do
        expect(result[:importmap_pins]).to eq([])
      end
    end
  end

  describe '#call when app.root raises' do
    let(:bad_app) { double('Rails::Application') }
    let(:result) { described_class.new(bad_app).call }

    before { allow(bad_app).to receive(:root).and_raise(StandardError, 'root boom') }

    it 'returns error hash' do
      expect(result[:error]).to eq('root boom')
    end
  end
end
