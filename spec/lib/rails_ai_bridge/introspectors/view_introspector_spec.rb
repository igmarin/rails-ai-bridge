# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ViewIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe '#call' do
    subject(:result) { introspector.call }

    it 'does not return an error' do
      expect(result).not_to have_key(:error)
    end

    it 'discovers layouts as file names only' do
      expect(result[:layouts]).to include('application.html.erb')
      result[:layouts].each do |layout|
        expect(layout).not_to include('/')
      end
    end

    it 'does not include directories in layouts' do
      result[:layouts].each do |layout|
        full_path = Rails.root.join('app/views/layouts', layout)
        expect(File.file?(full_path)).to be(true), "Expected #{layout} to be a file, not a directory"
      end
    end

    it 'discovers templates grouped by controller' do
      expect(result[:templates]).to have_key('posts')
      expect(result[:templates]['posts']).to include('index.html.erb')
      expect(result[:templates]['posts']).to include('show.html.erb')
    end

    it 'excludes partials from templates' do
      result[:templates].each_value do |templates|
        templates.each do |t|
          expect(t).not_to start_with('_')
        end
      end
    end

    it 'excludes layouts from templates' do
      expect(result[:templates]).not_to have_key('layouts')
    end

    it 'discovers partials in per_controller' do
      expect(result[:partials][:per_controller]).to have_key('posts')
      expect(result[:partials][:per_controller]['posts']).to include('_post.html.erb')
    end

    it 'returns shared partials as sorted array' do
      expect(result[:partials][:shared]).to be_an(Array)
    end

    it 'extracts helpers with methods' do
      helper_files = result[:helpers].pluck(:file)
      expect(helper_files).to include('application_helper.rb', 'posts_helper.rb')

      app_helper = result[:helpers].find { |h| h[:file] == 'application_helper.rb' }
      expect(app_helper[:methods]).to include('page_title')

      posts_helper = result[:helpers].find { |h| h[:file] == 'posts_helper.rb' }
      expect(posts_helper[:methods]).to include('post_excerpt')
    end

    it 'detects erb template engine' do
      expect(result[:template_engines]).to include('erb')
    end

    it 'returns view_components as empty when no components dir' do
      expect(result[:view_components]).to eq([])
    end

    context 'with view components' do
      let(:components_dir) { Rails.root.join('app/components').to_s }

      before do
        FileUtils.mkdir_p(components_dir)
        File.write(File.join(components_dir, 'alert_component.rb'), 'class AlertComponent; end')
        File.write(File.join(components_dir, 'badge_component.rb'), 'class BadgeComponent; end')
      end

      after { FileUtils.rm_rf(components_dir) }

      it 'discovers view components' do
        expect(result[:view_components]).to contain_exactly('alert_component', 'badge_component')
      end
    end

    context 'when view-layer directories are configured to custom paths' do
      let(:custom_context) do
        root_path = Dir.mktmpdir('rails-ai-bridge-view-paths')
        root = Pathname.new(root_path)
        views_dir = root.join('interface/templates')
        helpers_dir = root.join('interface/helpers')
        components_dir = root.join('interface/components')
        app = double(
          'Rails::Application',
          root:,
          paths: {
            'app/views' => [views_dir.to_s],
            'app/helpers' => [helpers_dir.to_s],
            'app/components' => [components_dir.to_s]
          }
        )

        { root_path:, views_dir:, helpers_dir:, components_dir:, introspector: described_class.new(app) }
      end

      after { FileUtils.rm_rf(custom_context[:root_path]) }

      before do
        FileUtils.mkdir_p(custom_context[:views_dir].join('reports'))
        FileUtils.mkdir_p(custom_context[:views_dir].join('layouts'))
        FileUtils.mkdir_p(custom_context[:helpers_dir])
        FileUtils.mkdir_p(custom_context[:components_dir])
        File.write(custom_context[:views_dir].join('layouts/application.html.erb'), '<main><%= yield %></main>')
        File.write(custom_context[:views_dir].join('reports/index.html.erb'), '<%= render "summary" %>')
        File.write(custom_context[:views_dir].join('reports/_summary.html.erb'), '<p>Summary</p>')
        File.write(custom_context[:helpers_dir].join('reports_helper.rb'), "module ReportsHelper\n  def report_title; end\nend\n")
        File.write(custom_context[:components_dir].join('summary_component.rb'), 'class SummaryComponent; end')
      end

      it 'discovers views, helpers, and components from configured logical paths' do
        custom_result = custom_context[:introspector].call

        expect(custom_result[:layouts]).to eq(['application.html.erb'])
        expect(custom_result[:templates]).to include('reports' => ['index.html.erb'])
        expect(custom_result[:partials][:per_controller]).to include('reports' => ['_summary.html.erb'])
        expect(custom_result[:helpers]).to include(a_hash_including(file: 'reports_helper.rb', methods: ['report_title']))
        expect(custom_result[:view_components]).to eq(['summary_component'])
      end
    end
  end
end
