# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Formatters::Sections::ControllersFormatter do
  def render(ctx)
    described_class.new(ctx).call
  end

  let(:base_context) do
    {
      controllers: {
        controllers: {
          'UsersController' => {
            parent_class: 'ApplicationController',
            api_controller: false,
            actions: %w[index show create],
            filters: [
              { kind: 'before_action', name: 'authenticate_user!' },
              { kind: 'before_action', name: 'set_user' }
            ],
            strong_params: %w[name email]
          },
          'PostsController' => {
            parent_class: 'ApplicationController',
            api_controller: true,
            actions: %w[index],
            filters: [],
            strong_params: []
          }
        }
      }
    }
  end

  # -------------------------------------------------------------------------
  # Guard clauses
  # -------------------------------------------------------------------------
  it 'returns nil when controllers key is absent' do
    expect(render({})).to be_nil
  end

  it 'returns nil when controllers data has an error' do
    expect(render({ controllers: { error: 'boom' } })).to be_nil
  end

  it 'returns nil when the controllers hash is empty' do
    expect(render({ controllers: { controllers: {} } })).to be_nil
  end

  # -------------------------------------------------------------------------
  # Header
  # -------------------------------------------------------------------------
  it 'includes the controller count in the section heading' do
    expect(render(base_context)).to include('Controllers (2)')
  end

  # -------------------------------------------------------------------------
  # Per-controller rendering
  # -------------------------------------------------------------------------
  it 'renders each controller name as a sub-heading' do
    output = render(base_context)
    expect(output).to include('### UsersController')
    expect(output).to include('### PostsController')
  end

  it 'renders the parent class' do
    expect(render(base_context)).to include('Parent: `ApplicationController`')
  end

  it 'omits the parent line when parent_class is absent' do
    ctx = { controllers: { controllers: { 'FooController' => { actions: ['index'] } } } }
    expect(render(ctx)).not_to include('Parent:')
  end

  it 'renders the API controller flag when true' do
    expect(render(base_context)).to include('API controller: yes')
  end

  it 'omits the API controller line when false' do
    output = render(base_context)
    expect(output.scan('API controller:').size).to eq(1)
  end

  it 'renders actions as a comma-separated list' do
    expect(render(base_context)).to include('Actions: `index`, `show`, `create`')
  end

  it 'omits the actions line when actions are absent' do
    ctx = { controllers: { controllers: { 'FooController' => {} } } }
    expect(render(ctx)).not_to include('Actions:')
  end

  # -------------------------------------------------------------------------
  # Filter rendering
  # -------------------------------------------------------------------------
  it 'renders filters with kind and name' do
    expect(render(base_context)).to include('before_action authenticate_user!')
    expect(render(base_context)).to include('before_action set_user')
  end

  it 'omits the filters line when filters are empty' do
    output = render(base_context)
    # PostsController has no filters — only one Filters: line should appear
    expect(output.scan('Filters:').size).to eq(1)
  end

  # -------------------------------------------------------------------------
  # Strong params
  # -------------------------------------------------------------------------
  it 'renders strong params as a comma-separated list' do
    expect(render(base_context)).to include('Strong params: `name`, `email`')
  end

  it 'omits the strong params line when empty' do
    output = render(base_context)
    # PostsController has no strong params — only one Strong params: line
    expect(output.scan('Strong params:').size).to eq(1)
  end

  # -------------------------------------------------------------------------
  # Error entries are skipped
  # -------------------------------------------------------------------------
  it 'skips controllers that have an error key' do
    ctx = {
      controllers: {
        controllers: {
          'BrokenController' => { error: 'load failed' },
          'WorkingController' => { actions: ['index'] }
        }
      }
    }
    output = render(ctx)
    expect(output).not_to include('BrokenController')
    expect(output).to include('WorkingController')
  end
end
