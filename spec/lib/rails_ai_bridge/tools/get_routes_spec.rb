# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::GetRoutes do
  describe '.call' do
    let(:routes_data) do
      {
        total_routes: 4,
        api_namespaces: ['api/v1'],
        by_controller: {
          'posts' => [
            { verb: 'GET', path: '/posts', action: 'index', name: 'posts' },
            { verb: 'POST', path: '/posts', action: 'create', name: nil }
          ],
          'api/v1/users' => [
            { verb: 'GET', path: '/api/v1/users', action: 'index', name: 'api_v1_users' },
            { verb: 'GET', path: '/api/v1/users/:id', action: 'show', name: 'api_v1_user' }
          ]
        }
      }
    end
    let(:response) { described_class.call(**params) }
    let(:content) { response.content.first[:text] }

    before do
      allow(described_class).to receive(:cached_section).with(:routes).and_return(routes_data)
    end

    context "with detail: 'summary'" do
      let(:params) { { detail: 'summary' } }

      it 'returns a summary of routes per controller' do
        expect(content).to include('# Routes Summary (4 total)')
        expect(content).to include('- **posts** — 2 routes (1 GET, 1 POST)')
        expect(content).to include('- **api/v1/users** — 2 routes (2 GET)')
        expect(content).to include('API namespaces: api/v1')
      end
    end

    context "with detail: 'standard' (default)" do
      let(:params) { {} }

      it 'returns a standard list of routes' do
        expect(content).to include('# Routes (4 total)')
        expect(content).to include('## api/v1/users')
        expect(content).to include('- `GET` `/api/v1/users` → index')
        expect(content).to include('## posts')
        expect(content).to include('- `POST` `/posts` → create')
      end
    end

    context "with detail: 'full'" do
      let(:params) { { detail: 'full' } }

      it 'returns a detailed markdown table of routes' do
        expect(content).to include('# Routes Full Detail (4 total)')
        expect(content).to include('| Verb | Path | Controller#Action | Helper | Params |')
        expect(content).to include('| GET | `/posts` | posts#index | - | - |')
        expect(content).to include('| POST | `/posts` | posts#create | - | - |')
      end
    end

    context 'when filtering by controller' do
      let(:params) { { controller: 'posts' } }

      it 'returns only the routes for that controller' do
        expect(content).to include('# Routes (2 total)')
        expect(content).not_to include('api/v1/users')
        expect(content).to include('## posts')
        expect(content).to include('- `GET` `/posts` → index')
      end

      context "with detail: 'full'" do
        let(:params) { { controller: 'posts', detail: 'full' } }

        it 'uses the filtered route count in the heading' do
          expect(content).to include('# Routes Full Detail (2 total)')
        end
      end
    end

    context 'when filtering by a controller that does not exist' do
      let(:params) { { controller: 'nonexistent' } }

      it 'returns a helpful message' do
        expect(content).to include("No routes for 'nonexistent'")
        expect(content).to include('Controllers: api/v1/users, posts')
      end
    end

    context 'when route introspection is not available' do
      let(:routes_data) { nil }
      let(:params) { {} }

      it 'returns an informative message' do
        expect(content).to include('Route introspection not available')
      end
    end

    context 'when route introspection has an error' do
      let(:routes_data) { { error: 'Something went wrong' } }
      let(:params) { {} }

      it 'returns the error message' do
        expect(content).to include('Route introspection failed: Something went wrong')
      end
    end

    context "with format: 'json'" do
      let(:params) { { format: 'json' } }

      it 'returns the routes payload as JSON' do
        parsed = JSON.parse(content)
        expect(parsed['total']).to eq(4)
        expect(parsed['controllers']).to include('posts', 'api/v1/users')
      end
    end

    context "with format: 'json' and controller filter" do
      let(:params) { { controller: 'posts', format: 'json' } }

      it 'returns only the filtered routes as JSON' do
        parsed = JSON.parse(content)
        expect(parsed['controllers'].keys).to eq(['posts'])
        expect(parsed['controllers']['posts'].size).to eq(2)
      end
    end

    context 'when routes include helpers and required params from the route set' do
      let(:routes_data) do
        {
          total_routes: 3,
          api_namespaces: [],
          by_controller: {
            'posts' => [
              { verb: 'GET', path: '/posts/:id', action: 'show', name: 'post', helper: 'post_path',
                required_params: ['id'] }
            ],
            'users' => [
              { verb: 'GET', path: '/legacy-ping', action: 'index' },
              { verb: 'GET', path: '/me', action: 'show', name: 'profile', helper: 'profile_path' }
            ]
          }
        }
      end

      context "with detail: 'summary'" do
        let(:params) { { detail: 'summary' } }

        it 'lists verb, path, and helper name without required params' do
          expect(content).to include('GET `/posts/:id` `post_path`')
          expect(content).to include('GET `/me` `profile_path`')
          expect(content).not_to include('required_params')
        end
      end

      context "with detail: 'standard'" do
        let(:params) { { detail: 'standard' } }

        it 'includes helper and required params for a named route' do
          expect(content).to include('`GET` `/posts/:id` → show (`post_path`, id)')
        end

        it 'does not invent a helper for an unnamed route' do
          expect(content).to include('`GET` `/legacy-ping` → index')
          expect(content).not_to include('legacy_ping_path')
          expect(content).not_to include('legacy-ping_path')
        end
      end

      context "with detail: 'full'" do
        let(:params) { { detail: 'full' } }

        it 'includes helper and required params for a named route' do
          expect(content).to include('| GET | `/posts/:id` | posts#show | post_path | id |')
        end

        it 'leaves the helper blank for an unnamed route' do
          expect(content).to include('| GET | `/legacy-ping` | users#index | - | - |')
        end
      end
    end
  end
end
