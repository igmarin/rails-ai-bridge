# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe RailsAiBridge::Introspectors::NonArModelsIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    context 'when app/models contains non-ActiveRecord classes' do
      it 'returns a list including plain Ruby classes under app/models' do
        result = introspector.call
        expect(result).not_to have_key(:error)
        names = (result[:non_ar_models] || []).pluck(:name)
        expect(names).to include('OrderCalculator')
      end

      it 'tags entries as POJO/Service with correct structure' do
        result = introspector.call
        row = result[:non_ar_models].find { |h| h[:name] == 'OrderCalculator' }
        expect(row[:tag]).to eq('POJO/Service')
        expect(row[:relative_path]).to eq('app/models/order_calculator.rb')
        expect(row).to have_key(:name)
      end

      it 'returns entries sorted by name' do
        result = introspector.call
        entries = result[:non_ar_models]
        names = entries.pluck(:name)
        expect(names).to eq(names.sort)
      end
    end

    context 'when app/models directory does not exist' do
      before do
        allow(Dir).to receive(:exist?).with("#{introspector.instance_variable_get(:@root)}/app/models").and_return(false)
      end

      it 'returns empty non_ar_models array' do
        result = introspector.call
        expect(result).to eq({ non_ar_models: [] })
      end
    end

    context 'when app/models is configured to a custom directory' do
      let(:custom_context) do
        root_path = Dir.mktmpdir('rails-ai-bridge-non-ar-paths')
        root = Pathname.new(root_path)
        models_dir = root.join('domain/models')
        app = double(
          'Rails::Application',
          root:,
          config: double(eager_load: true),
          eager_load!: nil,
          paths: { 'app/models' => [models_dir.to_s] }
        )

        {
          root_path: root_path,
          models_dir: models_dir,
          introspector: described_class.new(app),
          constant_name: "BillingPolicy#{SecureRandom.hex(4)}"
        }
      end

      after do
        # rubocop:disable RSpec/RemoveConst
        Object.send(:remove_const, custom_context[:constant_name]) if Object.const_defined?(custom_context[:constant_name], false)
        # rubocop:enable RSpec/RemoveConst
        FileUtils.rm_rf(custom_context[:root_path])
      end

      before do
        FileUtils.mkdir_p(custom_context[:models_dir])
        File.write(custom_context[:models_dir].join('billing_policy.rb'), <<~RUBY)
          class #{custom_context[:constant_name]}
          end
        RUBY
        load custom_context[:models_dir].join('billing_policy.rb')
      end

      it 'discovers non-ActiveRecord classes from the configured models path' do
        result = custom_context[:introspector].call

        expect(result).not_to have_key(:error)
        expect(result[:non_ar_models]).to include(
          a_hash_including(
            name: custom_context[:constant_name],
            relative_path: 'app/models/billing_policy.rb',
            tag: 'POJO/Service'
          )
        )
      end
    end

    context 'when eager loading fails' do
      before do
        # Mock the eager_load! method to raise an error
        allow(introspector).to receive(:eager_load!).and_raise(StandardError.new('Load failed'))
      end

      it 'handles errors gracefully and returns error hash' do
        result = introspector.call
        expect(result).to have_key(:error)
        expect(result[:error]).to be_a(String)
      end

      it 'sanitizes error messages to prevent path disclosure' do
        # Test with file path in error message
        allow(introspector).to receive(:eager_load!)
          .and_raise(StandardError.new('Failed to load /path/to/secret/file'))

        result = introspector.call
        expect(result[:error]).to eq('Failed to load /[REDACTED]')
        expect(result[:error]).not_to include('/path/to/secret/file')
      end

      it 'truncates long error messages' do
        long_message = 'a' * 250 # 250 character error message
        allow(introspector).to receive(:eager_load!)
          .and_raise(StandardError.new(long_message))

        result = introspector.call
        expect(result[:error].length).to be <= 200
        expect(result[:error]).to end_with('...')
      end
    end
  end

  describe '#collect_entries' do
    context 'security boundaries' do
      it 'filters classes to app/models directory only' do
        result = introspector.call
        entries = result[:non_ar_models] || []

        # All entries should be within app/models
        entries.each do |entry|
          expect(entry[:relative_path]).to start_with('app/models/')
        end
      end

      it 'validates class names before processing' do
        result = introspector.call
        entries = result[:non_ar_models] || []

        # All entries should have valid Ruby class names
        entries.each do |entry|
          name = entry[:name]
          expect(name).to match(/\A[A-Z][A-Za-z0-9_:]*\z/)
          expect(name).not_to include('.')
          expect(name).not_to be_nil
          expect(name).not_to be_empty
        end
      end

      it 'excludes ActiveRecord classes' do
        result = introspector.call
        entries = result[:non_ar_models] || []
        names = entries.pluck(:name)

        # Should not include any ActiveRecord models
        ar_models = ActiveRecord::Base.descendants.map(&:name)
        ar_models.compact!

        names.each do |name|
          expect(ar_models).not_to include(name)
        end
      end
    end
  end

  describe '#initialize' do
    it 'stores application root and app reference' do
      app = double('Rails::Application', root: '/path/to/app')
      introspector = described_class.new(app)

      expect(introspector.instance_variable_get(:@app)).to eq(app)
      expect(introspector.instance_variable_get(:@root)).to eq('/path/to/app')
    end
  end
end
