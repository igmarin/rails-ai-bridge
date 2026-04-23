# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::GetView do
  let(:view_data) do
    {
      layouts: %w[application admin],
      template_engines: %w[erb haml],
      templates: {
        'users' => ['index.html.erb', 'show.html.erb'],
        'posts' => ['_form.html.erb']
      },
      partials: {
        shared: ['_header.html.erb'],
        per_controller: {
          'users' => ['_user_card.html.erb'],
          'posts' => ['_post_item.html.erb']
        }
      },
      helpers: [
        { file: 'app/helpers/users_helper.rb', methods: ['full_name'] },
        { file: 'app/helpers/posts_helper.rb', methods: ['post_title'] }
      ],
      view_components: %w[UserAvatarComponent PostCardComponent]
    }
  end
  let(:response) { described_class.call(**params) }
  let(:content) { response.content.first[:text] }

  let(:specific_view_analysis) do
    {
      path: 'users/index.html.erb',
      template_engine: 'erb',
      partial: false,
      renders: ['users/_user_card.html.erb'],
      turbo_frames: ['user_list'],
      stimulus_controllers: ['user-search'],
      stimulus_actions: ['user-search#perform'],
      content: "<p>Users list</p>
<%= render 'users/user_card' %>
"
    }
  end

  before do
    allow(described_class).to receive(:cached_section).with(:views).and_return(view_data)
    allow(RailsAiBridge::ViewFileAnalyzer).to receive(:call).and_return(specific_view_analysis)

    # Stub formatters to ensure correct delegation
    allow(RailsAiBridge::Tools::GetView::SummaryFormatter).to receive(:new).and_call_original
    allow(RailsAiBridge::Tools::GetView::StandardFormatter).to receive(:new).and_call_original
    allow(RailsAiBridge::Tools::GetView::FullFormatter).to receive(:new).and_call_original
    allow(RailsAiBridge::Tools::GetView::SpecificViewFormatter).to receive(:new).and_call_original
  end

  describe '.call' do
    context 'when requesting a specific view path' do
      let(:params) { { path: 'users/index.html.erb' } }

      it 'delegates to SpecificViewFormatter' do
        allow(RailsAiBridge::Tools::GetView::SpecificViewFormatter).to receive(:new).and_call_original
        expect(content).to include('# View: users/index.html.erb')
      end

      it 'returns detailed analysis of that view file' do
        expect(content).to include('- Template engine: erb')
        expect(content).to include('- Partial: no')
        expect(content).to include('- Renders: users/_user_card.html.erb')
        expect(content).to include('## Source')
        expect(content).to include("```erb
<p>Users list</p>")
      end
    end

    context "with detail: 'summary'" do
      let(:params) { { detail: 'summary' } }

      it 'delegates to SummaryFormatter' do
        allow(RailsAiBridge::Tools::GetView::SummaryFormatter).to receive(:new).and_call_original
        expect(content).to include('# View Summary')
      end

      it 'returns a summary of view-layer components' do
        expect(content).to include('- Layouts: 2')
        expect(content).to include('- Template engines: erb, haml')
        expect(content).to include('- Shared partials: 1')
        expect(content).to include('- **users/** — 2 templates, 1 partials')
        expect(content).to include('- **posts/** — 1 templates, 1 partials')
      end
    end

    context "with detail: 'standard'" do
      let(:params) { { detail: 'standard' } }

      it 'delegates to StandardFormatter' do
        allow(RailsAiBridge::Tools::GetView::StandardFormatter).to receive(:new).and_call_original
        expect(content).to include('# Views')
      end

      it 'returns a standard list of templates and partials' do
        expect(content).to include('- Layouts: application, admin')
        expect(content).to include('## Templates by controller')
        expect(content).to include('- `users/`: index.html.erb, show.html.erb')
        expect(content).to include('## Shared Partials')
        expect(content).to include('- `_header.html.erb`')
      end
    end

    context "with detail: 'full'" do
      let(:params) { { detail: 'full' } }

      it 'delegates to FullFormatter' do
        allow(RailsAiBridge::Tools::GetView::FullFormatter).to receive(:new).and_call_original
        expect(content).to include('## Templates by controller') # from standard formatter
      end

      it 'returns full details including helpers and view components' do
        expect(content).to include('## Helpers')
        expect(content).to include('- `app/helpers/users_helper.rb`: full_name')
        expect(content).to include('## View Components')
        expect(content).to include('- `UserAvatarComponent`')
      end
    end

    context 'when filtering by controller' do
      let(:params) { { controller: 'users', detail: 'standard' } }

      it 'returns only views for that controller' do
        expect(content).to include('# Views for users')
        expect(content).to include('- `users/`: index.html.erb, show.html.erb')
        expect(content).not_to include('posts/')
      end
    end

    context 'when filtering by partial' do
      let(:params) { { partial: '_header', detail: 'standard' } }

      it 'returns only matching partials' do
        expect(content).to include('# Partials matching _header')
        expect(content).to include('## Shared Partials')
        expect(content).to include('- `_header.html.erb`')
        expect(content).not_to include('posts/')
      end
    end

    context 'when view introspection is not available' do
      let(:view_data) { nil }
      let(:params) { {} }

      it 'returns an informative message' do
        expect(content).to include('View introspection not available.')
      end
    end

    context 'when view introspection has an error' do
      let(:view_data) { { error: 'Something went wrong' } }
      let(:params) { {} }

      it 'returns the error message' do
        expect(content).to include('View introspection failed: Something went wrong')
      end
    end

    context 'when specific view path is outside app/views' do
      before do
        allow(RailsAiBridge::ViewFileAnalyzer).to receive(:call).and_raise(SecurityError, 'Path outside app/views')
      end

      let(:params) { { path: '../../config/database.yml' } }

      it 'returns a security error message' do
        expect(content).to include('Path outside app/views')
      end
    end

    context 'when specific view path is not found' do
      before do
        allow(RailsAiBridge::ViewFileAnalyzer).to receive(:call).and_raise(Errno::ENOENT)
      end

      let(:params) { { path: 'nonexistent/view.html.erb' } }

      it 'returns a file not found message' do
        expect(content).to include('Path not found: nonexistent/view.html.erb')
      end
    end
  end
end
