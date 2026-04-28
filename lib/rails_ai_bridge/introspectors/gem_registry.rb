# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Registry of gems that significantly affect how a Rails app works.
    # Keeping this data separate from GemIntrospector lets the logic file stay small
    # and makes the list easy to scan and extend.
    module GemRegistry
      NOTABLE_GEMS = {
        # Auth
        'devise' => { category: :auth, note: 'Authentication via Devise. Check User model for devise modules.' },
        'omniauth' => { category: :auth, note: 'OAuth integration via OmniAuth.' },
        'pundit' => { category: :auth, note: 'Authorization via Pundit policies in app/policies/.' },
        'cancancan' => { category: :auth, note: 'Authorization via CanCanCan abilities.' },
        'rodauth-rails' => { category: :auth, note: 'Authentication via Rodauth.' },
        'doorkeeper' => { category: :auth, note: 'OAuth 2 provider via Doorkeeper.' },
        'jwt' => { category: :auth, note: 'JWT token handling.' },

        # Background jobs
        'sidekiq' => { category: :jobs, note: 'Background jobs via Sidekiq. Check config/sidekiq.yml.' },
        'good_job' => { category: :jobs, note: 'Background jobs via GoodJob (Postgres-backed).' },
        'solid_queue' => { category: :jobs, note: 'Background jobs via SolidQueue (Rails 8 default).' },
        'delayed_job' => { category: :jobs, note: 'Background jobs via DelayedJob.' },
        'resque' => { category: :jobs, note: 'Background jobs via Resque (Redis-backed).' },
        'sneakers' => { category: :jobs, note: 'Background jobs via Sneakers (RabbitMQ).' },
        'shoryuken' => { category: :jobs, note: 'Background jobs via Shoryuken (AWS SQS).' },

        # Frontend
        'turbo-rails' => { category: :frontend, note: 'Hotwire Turbo for SPA-like navigation. Check Turbo Streams and Frames.' },
        'stimulus-rails' => { category: :frontend, note: 'Stimulus.js controllers in app/javascript/controllers/.' },
        'importmap-rails' => { category: :frontend, note: 'Import maps for JS (no bundler). Check config/importmap.rb.' },
        'jsbundling-rails' => { category: :frontend, note: 'JS bundling (esbuild/webpack/rollup). Check package.json.' },
        'cssbundling-rails' => { category: :frontend, note: 'CSS bundling. Check package.json for Tailwind/PostCSS/etc.' },
        'tailwindcss-rails' => { category: :frontend, note: 'Tailwind CSS integration.' },
        'react-rails' => { category: :frontend, note: 'React components in Rails views.' },
        'inertia_rails' => { category: :frontend, note: 'Inertia.js for SPA with Rails backend.' },

        # API
        'grape' => { category: :api, note: 'API framework via Grape. Check app/api/.' },
        'graphql' => { category: :api, note: 'GraphQL API. Check app/graphql/ for types and mutations.' },
        'jsonapi-serializer' => { category: :api, note: 'JSON:API serialization.' },
        'jbuilder' => { category: :api, note: 'JSON views via Jbuilder templates.' },
        'alba' => { category: :api, note: 'Fast JSON serialization via Alba.' },
        'blueprinter' => { category: :api, note: 'JSON serialization via Blueprinter.' },
        'fast_jsonapi' => { category: :api, note: 'Fast JSON:API serialization (Netflix).' },

        # Database
        'pg' => { category: :database, note: 'PostgreSQL adapter.' },
        'mysql2' => { category: :database, note: 'MySQL adapter.' },
        'sqlite3' => { category: :database, note: 'SQLite adapter.' },
        'redis' => { category: :database, note: 'Redis client. Used for caching/sessions/Action Cable.' },
        'solid_cache' => { category: :database, note: 'Database-backed cache (Rails 8).' },
        'solid_cable' => { category: :database, note: 'Database-backed Action Cable (Rails 8).' },

        # File handling
        'activestorage' => { category: :files, note: 'Active Storage for file uploads.' },
        'shrine' => { category: :files, note: 'File uploads via Shrine.' },
        'carrierwave' => { category: :files, note: 'File uploads via CarrierWave.' },
        'image_processing' => { category: :files, note: 'Image processing for Active Storage variants.' },
        'mini_magick' => { category: :files, note: 'ImageMagick wrapper for image manipulation.' },
        'aws-sdk-s3' => { category: :files, note: 'AWS S3 client for cloud storage.' },

        # Testing
        'rspec-rails' => { category: :testing, note: 'RSpec test framework. Tests in spec/.' },
        'minitest' => { category: :testing, note: 'Minitest framework. Tests in test/.' },
        'factory_bot_rails' => { category: :testing, note: 'Test fixtures via FactoryBot in spec/factories/.' },
        'faker' => { category: :testing, note: 'Fake data generation for tests.' },
        'capybara' => { category: :testing, note: 'Integration/system tests with Capybara.' },

        # Deployment
        'kamal' => { category: :deploy, note: 'Deployment via Kamal. Check config/deploy.yml.' },
        'capistrano' => { category: :deploy, note: 'Deployment via Capistrano. Check config/deploy/.' },

        # Monitoring
        'sentry-rails' => { category: :monitoring, note: 'Error tracking via Sentry.' },
        'datadog' => { category: :monitoring, note: 'APM and monitoring via Datadog.' },
        'scout_apm' => { category: :monitoring, note: 'APM via Scout.' },
        'newrelic_rpm' => { category: :monitoring, note: 'APM via New Relic.' },
        'skylight' => { category: :monitoring, note: 'Performance monitoring via Skylight.' },

        # Admin
        'activeadmin' => { category: :admin, note: 'Admin interface via ActiveAdmin.' },
        'administrate' => { category: :admin, note: 'Admin dashboard via Administrate.' },
        'avo' => { category: :admin, note: 'Admin panel via Avo.' },
        'trestle' => { category: :admin, note: 'Admin framework via Trestle.' },

        # Pagination
        'pagy' => { category: :pagination, note: 'Fast pagination via Pagy.' },
        'kaminari' => { category: :pagination, note: 'Pagination via Kaminari.' },
        'will_paginate' => { category: :pagination, note: 'Pagination via WillPaginate.' },

        # Search
        'ransack' => { category: :search, note: 'Search and filtering via Ransack.' },
        'pg_search' => { category: :search, note: 'PostgreSQL full-text search via pg_search.' },
        'searchkick' => { category: :search, note: 'Elasticsearch integration via Searchkick.' },
        'meilisearch-rails' => { category: :search, note: 'Meilisearch integration.' },

        # Forms
        'simple_form' => { category: :forms, note: 'Form builder via SimpleForm.' },
        'cocoon' => { category: :forms, note: 'Nested form support via Cocoon.' },

        # Utilities
        'nokogiri' => { category: :utilities, note: 'HTML/XML parsing via Nokogiri.' },
        'httparty' => { category: :utilities, note: 'HTTP client via HTTParty.' },
        'faraday' => { category: :utilities, note: 'HTTP client via Faraday.' },
        'rest-client' => { category: :utilities, note: 'HTTP client via RestClient.' },
        'flipper' => { category: :utilities, note: 'Feature flags via Flipper.' },
        'bullet' => { category: :utilities, note: 'N+1 query detection via Bullet.' },
        'rack-attack' => { category: :utilities, note: 'Rate limiting and throttling via Rack::Attack.' }
      }.freeze

      # Groups a flat list of notable-gem hashes by their :category key.
      # @param notable_gems [Array<Hash>] output of {GemIntrospector#detect_notable_gems}
      # @return [Hash{String => Array<String>}] category name → gem name list
      def self.categorize(notable_gems)
        notable_gems.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |gem_entry, grouped|
          grouped[gem_entry[:category]] << gem_entry[:name]
        end
      end
    end
  end
end
