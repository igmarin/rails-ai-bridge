# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe RailsAiBridge::Introspectors::ControllerIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'returns a controllers hash' do
      expect(result).to have_key(:controllers)
      expect(result[:controllers]).to be_a(Hash)
    end

    it 'discovers PostsController' do
      expect(result[:controllers]).to have_key('PostsController')
    end

    it 'omits UsersController when only User is excluded' do
      original_models = RailsAiBridge.configuration.excluded_models.dup
      RailsAiBridge.configuration.excluded_models += %w[User]

      filtered = described_class.new(Rails.application).call

      expect(filtered[:controllers]).not_to have_key('UsersController')
      expect(filtered[:controllers]).to have_key('PostsController')
    ensure
      RailsAiBridge.configuration.excluded_models = original_models
    end

    it 'omits UsersController when only the users table is excluded' do
      original_tables = RailsAiBridge.configuration.excluded_tables.dup
      RailsAiBridge.configuration.excluded_tables += %w[users]

      filtered = described_class.new(Rails.application).call

      expect(filtered[:controllers]).not_to have_key('UsersController')
      expect(filtered[:controllers]).to have_key('PostsController')
    ensure
      RailsAiBridge.configuration.excluded_tables = original_tables
    end

    it 'extracts all CRUD actions from PostsController' do
      actions = result[:controllers]['PostsController'][:actions]
      expect(actions).to include('index', 'show', 'new', 'create', 'edit', 'update', 'destroy')
    end

    it 'extracts filter with correct kind' do
      filters = result[:controllers]['PostsController'][:filters]
      set_post = filters.find { |f| f[:name] == 'set_post' }
      expect(set_post).not_to be_nil
      expect(set_post[:kind]).to eq('before')
    end

    context 'with inherited parent filters' do
      before do
        stub_const('StaffAuthController', Class.new(ApplicationController) do
          before_action :authenticate_staff!
          before_action :require_superadmin, only: :impersonate
        end)
        stub_const('AccountsController', Class.new(StaffAuthController) do
          def index; end
          def create; end
        end)
      end

      it 'includes inherited applicable filters and omits non-applicable only: filters' do
        filters = result[:controllers]['AccountsController'][:filters]
        names = filters.pluck(:name)

        expect(names).to include('authenticate_staff!')
        expect(names).not_to include('require_superadmin')
        expect(filters.find { |filter| filter[:name] == 'authenticate_staff!' }[:source])
          .to eq('StaffAuthController')
      end
    end

    it 'extracts parent class' do
      expect(result[:controllers]['PostsController'][:parent_class]).to eq('ApplicationController')
    end

    it 'extracts strong params methods' do
      params = result[:controllers]['PostsController'][:strong_params]
      expect(params).to eq(['post_params'])
    end

    it 'extracts respond_to formats from respond_to blocks' do
      formats = result[:controllers]['PostsController'][:respond_to_formats]
      expect(formats).to contain_exactly('html', 'json')
    end

    it 'detects API controllers' do
      expect(result[:controllers]).to have_key('Api::V1::BaseController')
      api = result[:controllers]['Api::V1::BaseController']
      expect(api[:api_controller]).to be true
      expect(api[:parent_class]).to include('API')
    end

    it 'marks non-API controllers as not api_controller' do
      expect(result[:controllers]['PostsController'][:api_controller]).to be false
    end

    it 'excludes ApplicationController' do
      expect(result[:controllers]).not_to have_key('ApplicationController')
    end

    it 'extracts concerns array' do
      concerns = result[:controllers]['PostsController'][:concerns]
      expect(concerns).to be_an(Array)
    end

    context 'with a controller that has complex respond_to' do
      let(:fixture_ctrl) { Rails.root.join('app/controllers/items_controller.rb').to_s }

      before do
        File.write(fixture_ctrl, <<~RUBY)
          class ItemsController < ApplicationController
            def index
              @items = []
              respond_to do |format|
                if @items.empty?
                  format.html { render :empty }
                end
                format.json { render json: @items }
                format.xml { render xml: @items }
              end
            end
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_ctrl) }

      it 'extracts all formats including those after nested end' do
        # Force controller discovery by loading the class
        load fixture_ctrl
        formats = result[:controllers]['ItemsController'][:respond_to_formats]
        expect(formats).to contain_exactly('html', 'json', 'xml')
      end
    end

    context 'when app/controllers is configured to a custom directory' do
      let(:custom_context) do
        root_path = Dir.mktmpdir('rails-ai-bridge-controller-paths')
        root = Pathname.new(root_path)
        controllers_dir = root.join('domain/controllers')
        constant_name = "CustomPathReports#{SecureRandom.hex(4).camelize}Controller"
        app = double('Rails::Application', root:, paths: { 'app/controllers' => [controllers_dir.to_s] },
                                           config: double('Rails::Configuration', eager_load: true), eager_load!: nil)

        {
          root_path: root_path,
          controllers_dir: controllers_dir,
          introspector: described_class.new(app),
          constant_name: constant_name,
          file_name: "#{constant_name.underscore}.rb"
        }
      end

      after { FileUtils.rm_rf(custom_context[:root_path]) }

      before do
        stub_const(custom_context[:constant_name], Class.new(ApplicationController) do
          def create; end
        end)

        FileUtils.mkdir_p(custom_context[:controllers_dir])
        File.write(custom_context[:controllers_dir].join(custom_context[:file_name]), <<~RUBY)
          class #{custom_context[:constant_name]} < ApplicationController
            def create
              respond_to do |format|
                format.json { render json: {} }
              end
            end

            private

            def report_params
              params.require(:report).permit(:name)
            end
          end
        RUBY
      end

      it 'reads source-derived controller metadata from the configured controllers path' do
        details = custom_context[:introspector].call[:controllers][custom_context[:constant_name]]

        expect(details[:strong_params]).to eq(['report_params'])
        expect(details[:respond_to_formats]).to eq(['json'])
      end
    end

    context 'when ActionController is not defined' do
      before { hide_const('ActionController::Base') }

      it 'returns empty controllers hash' do
        expect(result[:controllers]).to eq({})
      end
    end

    context 'when a controller raises during extraction' do
      before do
        allow(introspector).to receive(:extract_controller_details).and_raise(StandardError, 'ctrl boom')
        allow(Rails.logger).to receive(:debug)
      end

      it 'captures per-controller errors' do
        expect(result[:controllers].values).to all(include(error: 'ctrl boom'))
      end
    end

    context 'when call raises at top level' do
      before { allow(introspector).to receive(:eager_load_controllers!).and_raise(StandardError, 'eager boom') }

      it 'returns error hash' do
        expect(result[:error]).to eq('eager boom')
      end
    end
  end

  describe 'private methods' do
    describe '#extract_strong_params' do
      it 'returns empty array for nil source' do
        expect(introspector.send(:extract_strong_params, nil)).to eq([])
      end

      it 'finds params methods' do
        source = "def user_params\n  params.require(:user)\nend\ndef post_params\nend\n"
        expect(introspector.send(:extract_strong_params, source)).to contain_exactly('user_params', 'post_params')
      end
    end

    describe '#extract_respond_to' do
      it 'returns empty array for nil source' do
        expect(introspector.send(:extract_respond_to, nil)).to eq([])
      end

      it 'returns empty array when no respond_to block' do
        expect(introspector.send(:extract_respond_to, 'def index; end')).to eq([])
      end
    end

    describe '#read_source' do
      it 'returns nil when source path is nil' do
        ctrl = double('Ctrl', name: 'Nonexistent')
        allow(introspector).to receive(:source_path).and_return(nil)
        expect(introspector.send(:read_source, ctrl)).to be_nil
      end

      it 'returns nil when file does not exist' do
        ctrl = double('Ctrl', name: 'Nonexistent')
        allow(introspector).to receive(:source_path).and_return('/nonexistent.rb')
        expect(introspector.send(:read_source, ctrl)).to be_nil
      end

      it 'returns nil on file read error' do
        ctrl = double('Ctrl', name: 'Bad')
        path = '/tmp/test_ctrl_read.rb'
        File.write(path, 'class Bad; end')
        allow(introspector).to receive(:source_path).and_return(path)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(path).and_raise(StandardError, 'read error')
        expect(introspector.send(:read_source, ctrl)).to be_nil
      ensure
        allow(File).to receive(:read).and_call_original
        FileUtils.rm_f(path)
      end
    end

    describe '#extract_actions error handling' do
      it 'returns empty array on error' do
        ctrl = double('Ctrl')
        allow(ctrl).to receive(:action_methods).and_raise(StandardError, 'actions error')
        expect(introspector.send(:extract_actions, ctrl)).to eq([])
      end
    end

    describe '#extract_concerns error handling' do
      it 'returns empty array on error' do
        ctrl = double('Ctrl')
        allow(ctrl).to receive(:ancestors).and_raise(StandardError, 'concerns error')
        expect(introspector.send(:extract_concerns, ctrl)).to eq([])
      end
    end

    describe '#api_controller?' do
      it 'returns false when ActionController::API is not defined' do
        ctrl = double('Ctrl')
        hide_const('ActionController::API')
        expect(introspector.send(:api_controller?, ctrl)).to be false
      end
    end

    describe '#eager_load_controllers!' do
      it 'does not call eager_load! when config.eager_load is true' do
        allow(Rails.application.config).to receive(:eager_load).and_return(true)
        allow(Rails.application).to receive(:eager_load!)
        expect(Rails.application).not_to receive(:eager_load!)
        introspector.send(:eager_load_controllers!)
      end

      it 'rescues errors from eager_load!' do
        allow(Rails.application.config).to receive(:eager_load).and_return(false)
        allow(Rails.application).to receive(:eager_load!).and_raise(StandardError, 'load error')
        expect { introspector.send(:eager_load_controllers!) }.not_to raise_error
      end
    end

    describe '#discover_controllers without ActionController::API' do
      it 'still discovers controllers when API is not defined' do
        # Ensure PostsController is loaded
        expect(PostsController.name).to eq('PostsController')
        hide_const('ActionController::API')
        controllers = introspector.send(:discover_controllers)
        expect(controllers).to include(PostsController)
      end
    end
  end
end
