# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::ViewFileAnalyzer do
  let(:root) { Rails.root }

  describe '.call' do
    it 'returns metadata and content for a valid path under app/views' do
      result = described_class.call(root:, relative_path: 'posts/index.html.erb')

      expect(result[:path]).to eq('posts/index.html.erb')
      expect(result[:template_engine]).to eq('erb')
      expect(result[:partial]).to be(false)
      expect(result[:content]).to include('<h1>Posts</h1>')
    end

    it 'returns metadata for a view under a configured custom app/views path' do
      Dir.mktmpdir('rails-ai-bridge-view-detail') do |dir|
        app_root = Pathname.new(dir)
        views_dir = app_root.join('interface/templates')
        FileUtils.mkdir_p(views_dir.join('reports'))
        File.write(views_dir.join('reports/show.html.erb'), '<%= render "summary" %>')
        app = double('Rails::Application', root: app_root, paths: { 'app/views' => [views_dir.to_s] })

        result = described_class.call(root: app_root, app:, relative_path: 'reports/show.html.erb')

        expect(result[:path]).to eq('reports/show.html.erb')
        expect(result[:renders]).to include('summary')
        expect(result[:content]).to include('render "summary"')
      end
    end

    it 'raises SecurityError for parent-directory traversal' do
      expect do
        described_class.call(root:, relative_path: '../../../etc/passwd')
      end.to raise_error(SecurityError, /Path not allowed/)
    end

    it 'raises SecurityError for absolute paths outside app/views' do
      expect do
        described_class.call(root:, relative_path: '/etc/passwd')
      end.to raise_error(SecurityError, /Path not allowed/)
    end

    it 'raises Errno::ENOENT for a path inside app/views that does not exist' do
      expect do
        described_class.call(root:, relative_path: 'missing/template.html.erb')
      end.to raise_error(Errno::ENOENT)
    end
  end
end
