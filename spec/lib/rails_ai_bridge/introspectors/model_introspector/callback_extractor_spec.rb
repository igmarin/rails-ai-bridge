# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ModelIntrospector::CallbackExtractor do
  let(:excluded_prefixes) { %w[_ autosave validate_associated] }

  def cb(filter)
    instance_double(ActiveSupport::Callbacks::Callback, filter: filter)
  end

  def model_with(callbacks_by_type)
    model = Object.new
    described_class::CALLBACK_TYPES.each do |type|
      model.define_singleton_method(:"_#{type}_callbacks") do
        callbacks_by_type.fetch(type, [])
      end
    end
    model
  end

  describe '#call' do
    it 'groups named callbacks by type' do
      model = model_with(
        before_save: [cb(:set_defaults), cb('normalize_email')],
        after_create: [cb(:send_welcome)]
      )

      result = described_class.new(model, excluded_prefixes: excluded_prefixes).call

      expect(result).to eq(
        'before_save' => %w[set_defaults normalize_email],
        'after_create' => %w[send_welcome]
      )
    end

    it 'excludes Proc-based callbacks' do
      model = model_with(before_save: [cb(:keep), cb(-> { :skip })])
      result = described_class.new(model, excluded_prefixes: excluded_prefixes).call
      expect(result['before_save']).to eq(%w[keep])
    end

    it 'excludes callbacks whose filter starts with an excluded prefix' do
      model = model_with(
        after_save: [cb(:keep), cb(:_internal), cb(:autosave_associated_records_for_posts)]
      )
      result = described_class.new(model, excluded_prefixes: excluded_prefixes).call
      expect(result['after_save']).to eq(%w[keep])
    end

    it 'omits callback types with no remaining entries' do
      model = model_with(before_save: [cb(:_internal)], after_save: [cb(:keep)])
      result = described_class.new(model, excluded_prefixes: excluded_prefixes).call
      expect(result.keys).to eq(%w[after_save])
    end

    it 'returns {} when iteration raises' do
      model = Object.new
      # Missing _before_validation_callbacks etc. → NoMethodError → rescued.
      expect(described_class.new(model, excluded_prefixes: excluded_prefixes).call).to eq({})
    end
  end
end
