# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ActionTextIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'returns installed as false when ActionText is not loaded' do
      expect(result[:installed]).to be false
    end

    context 'with rich text macros in model source' do
      let(:fixture_model) { Rails.root.join('app/models/article.rb').to_s }

      before do
        File.write(fixture_model, <<~RUBY)
          class Article < ApplicationRecord
            has_rich_text :content
            has_rich_text :summary
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it 'detects all rich text fields' do
        fields = result[:rich_text_fields].select { |f| f[:model] == 'Article' }
        expect(fields.size).to eq(2)
        expect(fields.pluck(:field)).to contain_exactly('content', 'summary')
      end
    end

    context 'without rich text macros' do
      it 'returns empty rich_text_fields' do
        expect(result[:rich_text_fields]).to eq([])
      end
    end

    context 'with configured model paths' do
      let(:app_root) { Pathname.new(Dir.mktmpdir('rails-ai-bridge-action-text')) }
      let(:models_dir) { app_root.join('domain/models') }
      let(:custom_app) do
        double(
          'Rails::Application',
          root: app_root,
          paths: { 'app/models' => [models_dir.to_s] }
        )
      end

      after { FileUtils.rm_rf(app_root) }

      before do
        FileUtils.mkdir_p(models_dir)
        File.write(models_dir.join('article.rb'), <<~RUBY)
          class Article < ApplicationRecord
            has_rich_text :body
          end
        RUBY
      end

      it 'detects rich text macros outside conventional app/models' do
        expect(described_class.new(custom_app).call[:rich_text_fields]).to include(
          model: 'Article',
          field: 'body'
        )
      end
    end
  end
end
