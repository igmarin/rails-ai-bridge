# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ControllerIntrospector::FilterExtractor do
  def callback(filter:, kind: :before, if_conditions: nil, unless_conditions: nil)
    cb = Object.new
    cb.define_singleton_method(:filter) { filter }
    cb.define_singleton_method(:kind) { kind }
    cb.instance_variable_set(:@if, if_conditions)
    cb.instance_variable_set(:@unless, unless_conditions)
    cb
  end

  def controller_with(callbacks)
    ctrl = Object.new
    ctrl.define_singleton_method(:_process_action_callbacks) { callbacks }
    ctrl
  end

  describe '#call' do
    it 'returns [] when the controller does not expose _process_action_callbacks' do
      expect(described_class.new(Object.new).call).to eq([])
    end

    it 'returns named filters with their kind' do
      ctrl = controller_with([
                               callback(filter: :authenticate_user!, kind: :before),
                               callback(filter: :log_action, kind: :after)
                             ])

      expect(described_class.new(ctrl).call).to eq([
                                                     { name: 'authenticate_user!', kind: 'before' },
                                                     { name: 'log_action', kind: 'after' }
                                                   ])
    end

    it 'skips Proc filters and underscore-prefixed framework filters' do
      ctrl = controller_with([
                               callback(filter: :keep, kind: :before),
                               callback(filter: -> {}, kind: :before),
                               callback(filter: :_internal, kind: :before)
                             ])

      expect(described_class.new(ctrl).call).to eq([{ name: 'keep', kind: 'before' }])
    end

    it 'parses :only conditions from action_name equality checks' do
      ctrl = controller_with([
                               callback(
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
      ctrl = controller_with([
                               callback(
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
      ctrl = controller_with([
                               callback(
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
