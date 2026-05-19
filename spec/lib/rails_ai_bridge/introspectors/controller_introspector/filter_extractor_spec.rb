# frozen_string_literal: true

require 'spec_helper'

# Test helper module for building mock callback and controller objects
module TestHelpers
  # :reek:LongParameterList { max_params: 4 } - Acceptable for builder method
  def self.build_callback(filter:, kind: :before, if_conditions: nil, unless_conditions: nil)
    config = { filter: filter, kind: kind, if_conditions: if_conditions, unless_conditions: unless_conditions }
    create_callback_object(config)
  end

  def self.create_callback_object(config)
    callback = Object.new
    setup_callback_methods(callback, config)
    setup_callback_variables(callback, config)
    callback
  end

  def self.setup_callback_methods(callback, config)
    callback.define_singleton_method(:filter) { config[:filter] }
    callback.define_singleton_method(:kind) { config[:kind] }
  end

  def self.setup_callback_variables(callback, config)
    callback.instance_variable_set(:@if, config[:if_conditions])
    callback.instance_variable_set(:@unless, config[:unless_conditions])
  end

  def self.build_controller(callbacks)
    ctrl = Object.new
    ctrl.define_singleton_method(:_process_action_callbacks) { callbacks }
    ctrl
  end
end

RSpec.describe RailsAiBridge::Introspectors::ControllerIntrospector::FilterExtractor do
  let(:callback) { TestHelpers.method(:build_callback) }
  let(:controller_with) { TestHelpers.method(:build_controller) }

  describe '#call' do
    it 'returns [] when the controller does not expose _process_action_callbacks' do
      expect(described_class.new(Object.new).call).to eq([])
    end

    it 'returns named filters with their kind' do
      ctrl = controller_with.call([
                                    callback.call(filter: :authenticate_user!, kind: :before),
                                    callback.call(filter: :log_action, kind: :after)
                                  ])

      expect(described_class.new(ctrl).call).to eq([
                                                     { name: 'authenticate_user!', kind: 'before' },
                                                     { name: 'log_action', kind: 'after' }
                                                   ])
    end

    it 'skips Proc filters and underscore-prefixed framework filters' do
      ctrl = controller_with.call([
                                    callback.call(filter: :keep, kind: :before),
                                    callback.call(filter: -> {}, kind: :before),
                                    callback.call(filter: :_internal, kind: :before)
                                  ])

      expect(described_class.new(ctrl).call).to eq([{ name: 'keep', kind: 'before' }])
    end

    it 'parses :only conditions from action_name equality checks' do
      ctrl = controller_with.call([
                                    callback.call(
                                      filter: :require_admin,
                                      kind: :before,
                                      if_conditions: ["action_name == 'edit'", "action_name == 'update'"]
                                    )
                                  ])

      expect(described_class.new(ctrl).call).to eq([
                                                     { name: 'require_admin', kind: 'before',
                                                       only: %w[edit update] }
                                                   ])
    end

    it 'parses :except conditions from @unless' do
      ctrl = controller_with.call([
                                    callback.call(
                                      filter: :track,
                                      kind: :before,
                                      unless_conditions: ['action_name == "show"']
                                    )
                                  ])

      expect(described_class.new(ctrl).call).to eq([
                                                     { name: 'track', kind: 'before',
                                                       except: %w[show] }
                                                   ])
    end

    it 'omits :only / :except when no parseable conditions are found' do
      ctrl = controller_with.call([
                                    callback.call(
                                      filter: :run,
                                      kind: :before,
                                      if_conditions: ['some_other_check?'],
                                      unless_conditions: []
                                    )
                                  ])

      expect(described_class.new(ctrl).call).to eq([{ name: 'run', kind: 'before' }])
    end

    it 'returns [] when iteration raises' do
      ctrl = Object.new
      ctrl.define_singleton_method(:_process_action_callbacks) { raise StandardError, 'boom' }
      expect(described_class.new(ctrl).call).to eq([])
    end
  end
end
