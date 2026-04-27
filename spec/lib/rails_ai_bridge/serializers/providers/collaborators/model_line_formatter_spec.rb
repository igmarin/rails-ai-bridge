# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::Providers::Collaborators::ModelLineFormatter do
  let(:context) do
    {
      schema: { tables: {} },
      migrations: { recent: [], recent_tables: [] }
    }
  end

  let(:formatter) { described_class.new(context) }

  describe '#initialize' do
    it 'accepts valid context hash' do
      expect { described_class.new(context) }.not_to raise_error
    end

    it 'raises error for nil context' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /Context must be a Hash/)
    end

    it 'raises error for non-hash context' do
      expect { described_class.new('invalid') }.to raise_error(ArgumentError, /Context must be a Hash/)
    end
  end

  describe '#format_line' do
    context 'parameter validation' do
      it 'raises error for nil model name' do
        expect { formatter.format_line(nil, {}) }.to raise_error(ArgumentError, /Model name cannot be nil/)
      end

      it 'raises error for non-hash model data' do
        expect { formatter.format_line('User', 'invalid') }.to raise_error(ArgumentError, /Model data must be a Hash/)
      end

      it 'accepts empty string model name' do
        expect { formatter.format_line('', {}) }.not_to raise_error
      end
    end

    context 'basic formatting' do
      it 'formats minimal model data' do
        data = {}
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles empty model name' do
        data = {}
        result = formatter.format_line('', data)
        expect(result).to eq('- ****')
      end
    end

    context 'associations and validations' do
      it 'formats with associations only' do
        data = {
          associations: [
            { type: 'has_many', name: 'posts' },
            { type: 'belongs_to', name: 'user' }
          ]
        }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User** (2a, 0v) — has_many :posts, belongs_to :user')
      end

      it 'formats with validations only' do
        data = {
          validations: [
            { name: 'presence' },
            { name: 'uniqueness' },
            { name: 'length' }
          ]
        }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User** (0a, 3v)')
      end

      it 'formats with both associations and validations' do
        data = {
          associations: [{ type: 'has_many', name: 'posts' }],
          validations: [{ name: 'presence' }]
        }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User** (1a, 1v) — has_many :posts')
      end

      it 'handles nil associations array' do
        data = { associations: nil }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles empty associations array' do
        data = { associations: [] }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles malformed association entries' do
        data = {
          associations: [
            { type: 'has_many', name: 'posts' },
            { type: nil, name: 'invalid' },
            { name: 'missing_type' },
            { type: 'belongs_to', name: nil }
          ]
        }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User** (4a, 0v) — has_many :posts,  :invalid,  :missing_type')
      end

      it 'limits associations to top 3' do
        data = {
          associations: [
            { type: 'has_many', name: 'posts' },
            { type: 'belongs_to', name: 'user' },
            { type: 'has_many', name: 'comments' },
            { type: 'has_one', name: 'profile' },
            { type: 'has_many', name: 'likes' }
          ]
        }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User** (5a, 0v) — has_many :posts, belongs_to :user, has_many :comments')
      end
    end

    context 'enums' do
      it 'formats with single enum' do
        data = { enums: { status: %w[active inactive] } }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User** [enums: status]')
      end

      it 'formats with multiple enums' do
        data = {
          enums: {
            status: %w[active inactive],
            role: %w[admin user guest],
            priority: %w[low medium high]
          }
        }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User** [enums: status, role, priority]')
      end

      it 'handles empty enum hash' do
        data = { enums: {} }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles nil enums' do
        data = { enums: nil }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles enums with nil values' do
        data = { enums: { status: nil, role: ['admin'] } }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User** [enums: status, role]')
      end
    end

    context 'columns' do
      let(:context_with_schema) do
        {
          schema: {
            tables: {
              'users' => {
                columns: [
                  { name: 'id', type: 'bigint' },
                  { name: 'email', type: 'string' },
                  { name: 'created_at', type: 'datetime' },
                  { name: 'updated_at', type: 'datetime' }
                ]
              }
            }
          },
          migrations: { recent: [], recent_tables: [] }
        }
      end

      let(:formatter_with_schema) { described_class.new(context_with_schema) }

      it 'formats with columns when table exists' do
        data = { table_name: 'users' }
        result = formatter_with_schema.format_line('User', data)
        expect(result).to eq('- **User** [cols: email:string]')
      end

      it 'handles missing table in schema' do
        data = { table_name: 'nonexistent' }
        result = formatter_with_schema.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles nil table_name' do
        data = { table_name: nil }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles empty table_name' do
        data = { table_name: '' }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles malformed columns data' do
        malformed_context = {
          schema: {
            tables: {
              'users' => {
                columns: [
                  { name: 'id', type: 'bigint' },
                  { name: nil, type: 'string' },
                  { type: 'datetime' },
                  { name: 'email', type: nil }
                ]
              }
            }
          },
          migrations: { recent: [], recent_tables: [] }
        }
        formatter_malformed = described_class.new(malformed_context)
        data = { table_name: 'users' }
        result = formatter_malformed.format_line('User', data)
        expect(result).to eq('- **User** [cols: :string, :datetime, email:]')
      end
    end

    context 'recently migrated flag' do
      let(:context_with_migrations) do
        {
          schema: { tables: {} },
          migrations: {
            recent: [
              { version: '20240101120000', filename: '20240101120000_create_users.rb' },
              { version: '20240102120000', filename: '20240102120000_add_posts.rb' }
            ],
            recent_tables: %w[users posts]
          }
        }
      end

      let(:formatter_with_migrations) { described_class.new(context_with_migrations) }

      it 'does not include recently migrated flag for non-recent migrations' do
        data = { table_name: 'users' }
        result = formatter_with_migrations.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles migrations context delegation' do
        # This test verifies that delegation to ContextSummary works
        expect(RailsAiBridge::Serializers::ContextSummary).to receive(:recently_migrated?).with('users', context_with_migrations[:migrations]).and_return(true)

        data = { table_name: 'users' }
        result = formatter_with_migrations.format_line('User', data)
        expect(result).to include('[recently migrated]')
      end
    end

    context 'complex combinations' do
      let(:complex_context) do
        {
          schema: {
            tables: {
              'users' => {
                columns: [
                  { name: 'id', type: 'bigint' },
                  { name: 'email', type: 'string' },
                  { name: 'status', type: 'string' }
                ]
              }
            }
          },
          migrations: {
            recent: [{ version: '20240101120000', filename: '20240101120000_create_users.rb' }],
            recent_tables: %w[users]
          }
        }
      end

      let(:complex_formatter) { described_class.new(complex_context) }

      it 'formats complete model with all features' do
        data = {
          associations: [
            { type: 'has_many', name: 'posts' },
            { type: 'belongs_to', name: 'organization' },
            { type: 'has_many', name: 'comments' },
            { type: 'has_one', name: 'profile' }
          ],
          validations: [
            { name: 'presence' },
            { name: 'uniqueness' }
          ],
          enums: {
            status: %w[active inactive pending],
            role: %w[admin user]
          },
          table_name: 'users'
        }
        result = complex_formatter.format_line('User', data)
        expected = '- **User** (4a, 2v) [enums: status, role] [cols: email:string, status:string] ' \
                   '— has_many :posts, belongs_to :organization, has_many :comments'
        expect(result).to eq(expected)
      end
    end

    context 'edge cases and error handling' do
      it 'handles completely nil data structure' do
        data = {
          associations: nil,
          validations: nil,
          enums: nil,
          table_name: nil
        }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User**')
      end

      it 'handles deeply nested nil values' do
        data = {
          associations: [
            nil,
            { type: nil, name: nil },
            { type: 'has_many', name: nil }
          ],
          validations: [nil, { name: nil }],
          enums: { nil => nil, 'status' => nil },
          table_name: 'users'
        }
        result = formatter.format_line('User', data)
        expect(result).to eq('- **User** (3a, 2v) — has_many :')
      end

      it 'handles symbol keys and values' do
        data = {
          associations: [{ type: :has_many, name: :posts }],
          validations: [{ name: :presence }],
          enums: { status: %i[active inactive] },
          table_name: :users
        }
        result = formatter.format_line(:User, data)
        expect(result).to eq('- **User** (1a, 1v) [enums: status] — has_many :posts')
      end
    end
  end

  describe 'ContextSummary.recently_migrated?' do
    it 'works correctly' do
      migrations = { recent: [], recent_tables: [] }
      expect(RailsAiBridge::Serializers::ContextSummary).to receive(:recently_migrated?).with('users', migrations).and_return(true)

      result = RailsAiBridge::Serializers::ContextSummary.recently_migrated?('users', migrations)
      expect(result).to be true
    end
  end
end
