# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::I18nIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'returns default locale as en' do
      expect(result[:default_locale]).to eq('en')
    end

    it 'returns available locales including en' do
      expect(result[:available_locales]).to include('en')
      expect(result[:available_locales]).to all(be_a(String))
    end

    it 'returns backend class name as a non-empty string' do
      expect(result[:backend]).to be_a(String)
      expect(result[:backend]).not_to be_empty
    end

    it 'discovers locale files with correct names' do
      files = result[:locale_files].pluck(:file)
      expect(files).to include('en.yml')
    end

    # en.yml has: en > hello, en > posts > index > title, en > posts > show > title
    # That's 3 leaf keys
    it 'counts keys accurately in locale files' do
      en_file = result[:locale_files].find { |f| f[:file] == 'en.yml' }
      expect(en_file[:key_count]).to eq(3)
    end

    it 'does not have parse_error on valid YAML' do
      en_file = result[:locale_files].find { |f| f[:file] == 'en.yml' }
      expect(en_file).not_to have_key(:parse_error)
    end

    it 'returns correct total_locale_files count' do
      expect(result[:total_locale_files]).to be >= 1
      expect(result[:total_locale_files]).to eq(result[:locale_files].size)
    end

    context 'with invalid YAML locale file' do
      let(:bad_locale) { Rails.root.join('config/locales/bad.yml').to_s }

      before do
        File.write(bad_locale, 'invalid: yaml: [broken: {')
      end

      after { FileUtils.rm_f(bad_locale) }

      it 'marks the file with parse_error' do
        bad_file = result[:locale_files].find { |f| f[:file] == 'bad.yml' }
        expect(bad_file[:parse_error]).to be true
      end
    end

    context 'with a .rb locale file' do
      let(:rb_locale) { Rails.root.join('config/locales/custom.rb').to_s }

      before { File.write(rb_locale, "I18n.backend.store_translations(:en, hello: 'Hi')") }
      after { FileUtils.rm_f(rb_locale) }

      it 'includes .rb locale files without key_count' do
        rb_file = result[:locale_files].find { |f| f[:file] == 'custom.rb' }
        expect(rb_file).not_to be_nil
        expect(rb_file).not_to have_key(:key_count)
      end
    end
  end

  describe '#call with no config/locales directory' do
    let(:app_root) { Pathname.new(Dir.mktmpdir('no-locales')) }
    let(:custom_app) { double('Rails::Application', root: app_root) }
    let(:result) { described_class.new(custom_app).call }

    after { FileUtils.rm_rf(app_root) }

    it 'returns empty array for locale_files' do
      expect(result[:locale_files]).to eq([])
    end

    it 'returns 0 for total_locale_files' do
      expect(result[:total_locale_files]).to eq(0)
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
