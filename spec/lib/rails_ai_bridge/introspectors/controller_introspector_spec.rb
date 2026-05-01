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
        app = double('Rails::Application', root: root, paths: { 'app/controllers' => [controllers_dir.to_s] })

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
  end
end
