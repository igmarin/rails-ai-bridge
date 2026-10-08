# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::GetControllers do
  before { described_class.reset_cache! }

  describe 'confidence tags' do
    let(:controllers) do
      {
        'UsersController' => {
          actions: %w[index],
          filters: [{ kind: 'before_action', name: 'authenticate_user!', provenance: :reflection }],
          strong_params: %w[name email],
          strong_params_provenance: :regex,
          parent_class: 'ApplicationController'
        }
      }
    end

    before do
      allow(described_class).to receive(:cached_section).with(:controllers).and_return({ controllers: controllers })
    end

    around do |example|
      original = RailsAiBridge.configuration.confidence_tags_enabled
      begin
        example.run
      ensure
        RailsAiBridge.configuration.confidence_tags_enabled = original
      end
    end

    it 'tags regex-derived strong params as inferred on a single controller' do
      text = described_class.call(controller: 'UsersController').content.first[:text]

      expect(text).to include('- `name` [INFERRED]')
    end

    it 'renders a verification footer that counts facts by source' do
      text = described_class.call(controller: 'UsersController').content.first[:text]

      expect(text).to include('Verification: [VERIFIED] reflection (1) · [INFERRED] regex (2)')
    end

    it 'tags the strong params line in the full view' do
      text = described_class.call(detail: 'full').content.first[:text]

      expect(text).to include('- Strong params: name, email [INFERRED]')
    end

    it 'keeps verified filter lines free of inline tags, since the footer counts them' do
      text = described_class.call(controller: 'UsersController').content.first[:text]

      expect(text).to include('- `before_action` **authenticate_user!**')
      expect(text).not_to include('authenticate_user!** [VERIFIED]')
    end

    it 'counts payloads without provenance by the origin of each field' do
      allow(described_class).to receive(:cached_section).with(:controllers).and_return(
        { controllers: { 'LegacyController' => { filters: [{ kind: 'before_action', name: 'auth' }], strong_params: %w[name email] } } }
      )

      text = described_class.call(controller: 'LegacyController').content.first[:text]

      expect(text).to include('Verification: [VERIFIED] reflection (1) · [INFERRED] regex (2)')
    end

    it 'renders no footer for a controller with no filters or strong params' do
      allow(described_class).to receive(:cached_section).with(:controllers).and_return(
        { controllers: { 'PingController' => { actions: %w[show] } } }
      )

      text = described_class.call(controller: 'PingController').content.first[:text]

      expect(text).not_to include('Verification:')
    end

    it 'renders no tags when confidence tags are disabled' do
      RailsAiBridge.configuration.confidence_tags_enabled = false
      text = described_class.call(controller: 'UsersController').content.first[:text]

      expect(text).not_to match(/\[(VERIFIED|INFERRED)\]/)
    end
  end

  describe 'detail parameter' do
    before do
      controllers = {
        'UsersController' => {
          actions: %w[index show create],
          filters: [{ kind: 'before_action', name: 'authenticate_user!' }],
          strong_params: %w[name email],
          parent_class: 'ApplicationController'
        },
        'PostsController' => {
          actions: %w[index show],
          filters: [],
          strong_params: %w[title body]
        }
      }
      allow(described_class).to receive(:cached_section).with(:controllers).and_return({
                                                                                         controllers: controllers
                                                                                       })
    end

    it 'returns names with action counts for detail:summary' do
      result = described_class.call(detail: 'summary')
      text = result.content.first[:text]
      expect(text).to include('**UsersController** — 3 actions')
      expect(text).to include('**PostsController** — 2 actions')
    end

    it 'returns names with action names for detail:standard' do
      result = described_class.call(detail: 'standard')
      text = result.content.first[:text]
      expect(text).to include('**UsersController** — index, show, create')
    end

    it 'returns everything for detail:full' do
      result = described_class.call(detail: 'full')
      text = result.content.first[:text]
      expect(text).to include('## UsersController')
      expect(text).to include('Filters:')
      expect(text).to include('authenticate_user!')
    end

    it 'always returns full detail for specific controller' do
      result = described_class.call(controller: 'UsersController', detail: 'summary')
      text = result.content.first[:text]
      expect(text).to include('# UsersController')
      expect(text).to include('## Actions')
      expect(text).to include('## Filters')
    end

    it 'supports case-insensitive controller lookup' do
      result = described_class.call(controller: 'userscontroller')
      text = result.content.first[:text]
      expect(text).to include('# UsersController')
    end

    it 'handles missing controllers gracefully' do
      allow(described_class).to receive(:cached_section).with(:controllers).and_return(nil)
      result = described_class.call(detail: 'summary')
      text = result.content.first[:text]
      expect(text).to include('not available')
    end
  end
end
