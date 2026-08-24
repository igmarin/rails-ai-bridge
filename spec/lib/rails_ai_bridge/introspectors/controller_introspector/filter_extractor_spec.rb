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

  describe 'inherited ActionController filters' do
    subject(:filters) { described_class.new(child_class).call }

    let(:parent_class) do
      Class.new(ApplicationController) do
        def self.name
          'InheritedFiltersParentController'
        end

        before_action :authenticate_user!
        before_action :require_admin, only: :admin_panel
        after_action :write_audit, except: :index
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        def self.name
          'InheritedFiltersChildController'
        end

        before_action :set_user, only: :show

        def index; end
        def show; end
        def create; end
      end
    end

    def filter_named(name)
      filters.find { |filter| filter[:name] == name }
    end

    it 'includes inherited applicable filters with their source class' do
      auth = filter_named('authenticate_user!')
      expect(auth).to include(kind: 'before', source: 'InheritedFiltersParentController')
    end

    it 'omits inherited only: filters that do not apply to any child action' do
      expect(filter_named('require_admin')).to be_nil
    end

    it 'keeps except: filters that still apply to some child action' do
      audit = filter_named('write_audit')
      expect(audit).to include(kind: 'after', except: ['index'], source: 'InheritedFiltersParentController')
    end

    it 'extracts only: from ActionFilter conditions and tags the defining class' do
      expect(filter_named('set_user')).to include(
        kind: 'before',
        only: ['show'],
        source: 'InheritedFiltersChildController'
      )
    end

    it 'omits parent filters the child skipped' do
      child_class.skip_before_action :authenticate_user!

      expect(described_class.new(child_class).call.pluck(:name))
        .not_to include('authenticate_user!')
    end
  end

  describe 'private method edge cases' do
    describe '#controller_actions' do
      it 'returns empty array when controller does not respond to action_methods' do
        ctrl = Object.new
        extractor = described_class.new(ctrl)
        expect(extractor.send(:controller_actions)).to eq([])
      end

      it 'returns empty array on error' do
        ctrl = double('Ctrl')
        allow(ctrl).to receive(:action_methods).and_raise(StandardError, 'actions error')
        extractor = described_class.new(ctrl)
        expect(extractor.send(:controller_actions)).to eq([])
      end
    end

    describe '#controller_lineage' do
      it 'returns only the controller when it is not a Class' do
        ctrl = Object.new
        extractor = described_class.new(ctrl)
        expect(extractor.send(:controller_lineage)).to eq([ctrl])
      end
    end

    describe '#safe_callbacks' do
      it 'returns empty array on error' do
        klass = double('Klass')
        allow(klass).to receive(:_process_action_callbacks).and_raise(StandardError, 'callbacks error')
        extractor = described_class.new(Object.new)
        expect(extractor.send(:safe_callbacks, klass)).to eq([])
      end
    end

    describe '#framework_controller?' do
      it 'returns true for ActionController::Base' do
        extractor = described_class.new(ApplicationController)
        expect(extractor.send(:framework_controller?, ActionController::Base)).to be true
      end

      it 'returns true for nil name' do
        anon = Class.new
        extractor = described_class.new(ApplicationController)
        expect(extractor.send(:framework_controller?, anon)).to be true
      end

      it 'returns false for user-defined controllers' do
        extractor = described_class.new(ApplicationController)
        expect(extractor.send(:framework_controller?, PostsController)).to be false
      end
    end

    describe '#extract_action_conditions with nil' do
      it 'returns empty array for nil conditions' do
        extractor = described_class.new(ApplicationController)
        expect(extractor.send(:extract_action_conditions, nil)).to eq([])
      end
    end

    describe '#parse_action_condition with ActionFilter' do
      it 'extracts actions from ActionFilter object' do
        condition = double('ActionFilter')
        allow(condition).to receive(:instance_variable_defined?).with(:@actions).and_return(true)
        allow(condition).to receive(:instance_variable_get).with(:@actions).and_return(%i[index show])
        extractor = described_class.new(ApplicationController)
        expect(extractor.send(:parse_action_condition, condition)).to eq(%w[index show])
      end

      it 'returns nil when condition has no @actions and no action_name match' do
        condition = double('Condition')
        allow(condition).to receive(:instance_variable_defined?).with(:@actions).and_return(false)
        allow(condition).to receive(:to_s).and_return('some_condition?')
        extractor = described_class.new(ApplicationController)
        expect(extractor.send(:parse_action_condition, condition)).to be_nil
      end
    end

    describe '#included_in_effective_chain? with empty child chain' do
      it 'returns true when child chain is empty' do
        ctrl = Object.new
        ctrl.define_singleton_method(:_process_action_callbacks) { [] }
        extractor = described_class.new(ctrl)
        callback = TestHelpers.build_callback(filter: :test_filter, kind: :before)
        expect(extractor.send(:included_in_effective_chain?, callback)).to be true
      end
    end

    describe '#inherited_into_child_chain? edge cases' do
      it 'returns false when controller is not a Class' do
        ctrl = Object.new
        extractor = described_class.new(ctrl)
        expect(extractor.send(:inherited_into_child_chain?)).to be false
      end

      it 'returns false when parent does not respond to _process_action_callbacks' do
        ctrl = Class.new do
          def self.name
            'TestNoCallbacksParent'
          end
        end
        extractor = described_class.new(ctrl)
        expect(extractor.send(:inherited_into_child_chain?)).to be false
      end

      it 'returns false when parent chain is empty' do
        parent = Class.new(ApplicationController) do
          def self.name
            'EmptyChainParent'
          end
        end
        allow(parent).to receive(:_process_action_callbacks).and_return([])
        ctrl = Class.new(parent) do
          def self.name
            'EmptyChainChild'
          end
        end
        allow(ctrl).to receive(:_process_action_callbacks).and_return([])
        extractor = described_class.new(ctrl)
        expect(extractor.send(:inherited_into_child_chain?)).to be false
      end
    end

    describe '#source_class_name with framework controller owner' do
      it 'returns nil when the callback owner is a framework controller' do
        extractor = described_class.new(ApplicationController)
        # ActionController::Base is a framework controller
        callback = TestHelpers.build_callback(filter: :test_filter, kind: :before)
        allow(ActionController::Base).to receive(:_process_action_callbacks).and_return([callback])
        result = extractor.send(:source_class_name, callback)
        expect(result).to be_nil
      end
    end
  end
end
