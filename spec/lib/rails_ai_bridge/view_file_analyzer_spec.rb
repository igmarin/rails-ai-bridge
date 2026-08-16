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

    it 'extracts renders, turbo frames, and stimulus metadata from a view file' do
      Dir.mktmpdir('rails-ai-bridge-view-metadata') do |dir|
        app_root = Pathname.new(dir)
        views_dir = app_root.join('app/views/widgets')
        FileUtils.mkdir_p(views_dir)
        File.write(views_dir.join('index.html.erb'), <<~ERB)
          <%= turbo_frame_tag "widget_list" do %>
            <div data-controller="widget-search filter" data-action="input->widget-search#perform click->filter#toggle">
              <%= render "widgets/card" %>
              <%= render partial: "shared/flash" %>
            </div>
          <% end %>
        ERB

        result = described_class.call(root: app_root, relative_path: 'widgets/index.html.erb')

        expect(result[:renders]).to eq(['shared/flash', 'widgets/card'])
        expect(result[:turbo_frames]).to eq(['widget_list'])
        expect(result[:stimulus_controllers]).to eq(%w[filter widget-search])
        expect(result[:stimulus_actions]).to eq(['click->filter#toggle', 'input->widget-search#perform'])
      end
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

    it 'raises SecurityError when a symlink under app/views points outside views' do
      Dir.mktmpdir('rails-ai-bridge-view-symlink') do |dir|
        app_root = Pathname.new(dir)
        views_dir = app_root.join('app/views/leaks')
        FileUtils.mkdir_p(views_dir)
        secret = app_root.join('secret.txt')
        File.write(secret, 'TOP SECRET')
        File.symlink(secret, views_dir.join('secret.html.erb'))

        expect do
          described_class.call(root: app_root, relative_path: 'leaks/secret.html.erb')
        end.to raise_error(SecurityError, /Path not allowed/)
      end
    end

    it 'raises SecurityError when a symlink under a custom views path escapes every configured root' do
      Dir.mktmpdir('rails-ai-bridge-view-custom-symlink') do |dir|
        app_root = Pathname.new(dir)
        views_dir = app_root.join('interface/templates')
        FileUtils.mkdir_p(views_dir.join('reports'))
        secret = app_root.join('credentials.txt')
        File.write(secret, 'LEAK')
        File.symlink(secret, views_dir.join('reports/show.html.erb'))
        app = double('Rails::Application', root: app_root, paths: { 'app/views' => [views_dir.to_s] })

        expect do
          described_class.call(root: app_root, app:, relative_path: 'reports/show.html.erb')
        end.to raise_error(SecurityError, /Path not allowed/)
      end
    end

    it 'allows a symlink that resolves into another configured app/views root' do
      Dir.mktmpdir('rails-ai-bridge-view-cross-root') do |dir|
        app_root = Pathname.new(dir)
        primary = app_root.join('interface/templates')
        secondary = app_root.join('admin/templates')
        FileUtils.mkdir_p(primary.join('reports'))
        FileUtils.mkdir_p(secondary)
        File.write(secondary.join('shared.html.erb'), '<%= turbo_frame_tag "shared" %>')
        File.symlink(secondary.join('shared.html.erb'), primary.join('reports/show.html.erb'))
        app = double('Rails::Application', root: app_root, paths: { 'app/views' => [primary.to_s, secondary.to_s] })

        result = described_class.call(root: app_root, app:, relative_path: 'reports/show.html.erb')

        expect(result[:content]).to include('turbo_frame_tag "shared"')
        expect(result[:turbo_frames]).to include('shared')
      end
    end
  end
end
