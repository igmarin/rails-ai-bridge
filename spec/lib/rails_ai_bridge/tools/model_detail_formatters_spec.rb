# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'RailsAiBridge::Tools::ModelDetails formatters' do
  let(:models) do
    {
      'User' => {
        table_name: 'users',
        associations: [
          { type: 'has_many', name: 'posts' },
          { type: 'has_one', name: 'profile' }
        ],
        validations: [
          { kind: 'presence', attributes: ['email'], options: {} }
        ],
        enums: { role: %w[admin member] },
        scopes: %w[active recent],
        callbacks: { before_save: ['encrypt_password'] },
        concerns: ['Trackable'],
        instance_methods: ['full_name']
      },
      'Post' => {
        table_name: 'posts',
        associations: [{ type: 'belongs_to', name: 'user' }],
        validations: []
      }
    }
  end

  describe RailsAiBridge::Tools::ModelDetails::SummaryFormatter do
    subject(:output) { described_class.new(models: models).call }

    it 'lists model names' do
      expect(output).to include('- Post')
      expect(output).to include('- User')
    end

    it 'includes total count' do
      expect(output).to include('2')
    end

    it 'does not include association counts or details' do
      expect(output).not_to include('associations')
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::StandardFormatter do
    subject(:output) { described_class.new(models: models).call }

    it 'includes model names in bold' do
      expect(output).to include('**User**')
      expect(output).to include('**Post**')
    end

    it 'includes association and validation counts for User' do
      expect(output).to include('2 associations')
      expect(output).to include('1 validations')
    end

    it 'includes a hint to use model: for full detail' do
      expect(output).to include('model:"Name"')
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::FullFormatter do
    subject(:output) { described_class.new(models: models).call }

    it 'includes model names in bold' do
      expect(output).to include('**User**')
    end

    it 'includes association type and name' do
      expect(output).to include('has_many :posts')
    end

    it 'includes table name' do
      expect(output).to include('table: users')
    end

    it 'includes navigation hint' do
      expect(output).to include('model:"Name"')
    end
  end

  describe RailsAiBridge::Tools::ModelDetails::SingleModelFormatter do
    subject(:output) { described_class.new(name: 'User', data: models['User']).call }

    it 'renders model name as top-level header' do
      expect(output).to include('# User')
    end

    it 'renders table name' do
      expect(output).to include('**Table:** `users`')
    end

    it 'renders associations section' do
      expect(output).to include('## Associations')
      expect(output).to include('`has_many` **posts**')
    end

    it 'renders validations section' do
      expect(output).to include('## Validations')
      expect(output).to include('`presence` on email')
    end

    it 'renders enums section' do
      expect(output).to include('## Enums')
      expect(output).to include('`role`: admin, member')
    end

    it 'renders scopes section' do
      expect(output).to include('## Scopes')
      expect(output).to include('`active`')
    end

    it 'renders callbacks section' do
      expect(output).to include('## Callbacks')
      expect(output).to include('`before_save`: encrypt_password')
    end

    it 'renders concerns section' do
      expect(output).to include('## Concerns')
      expect(output).to include('Trackable')
    end

    it 'renders instance methods section' do
      expect(output).to include('## Key instance methods')
      expect(output).to include('`full_name`')
    end
  end
end
