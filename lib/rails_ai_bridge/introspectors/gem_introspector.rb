# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Analyzes Gemfile.lock to identify installed gems and
    # map them to known patterns/frameworks the AI should know about.
    class GemIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      # Parse +Gemfile.lock+ and classify notable gems.
      #
      # @return [Hash] gem analysis with +:total_gems+, +:ruby_version+,
      #   +:notable_gems+, and +:categories+; or +{ error: message }+ when the
      #   lockfile is absent or unreadable
      def call
        lock_path = File.join(app.root, 'Gemfile.lock')
        return { error: 'No Gemfile.lock found' } unless File.exist?(lock_path)

        specs   = parse_lockfile(lock_path)
        notable = detect_notable_gems(specs)

        {
          total_gems: specs.size,
          ruby_version: specs['ruby']&.first,
          notable_gems: notable,
          categories: GemRegistry.categorize(notable)
        }
      rescue StandardError => error
        { error: "GemIntrospector failed: #{error.class}" }
      end

      private

      def parse_lockfile(path)
        gems = {}
        in_gems = false

        File.readlines(path).each do |line|
          if line.strip == 'GEM'
            in_gems = true
            next
          elsif in_gems && line.match?(/^\S/) && !line.strip.start_with?('remote:', 'specs:')
            in_gems = false
          end

          if in_gems && (match = line.match(/^\s{4}(\S+)\s+\((.+)\)/))
            gems[match[1]] = match[2]
          end
        end

        gems
      end

      def detect_notable_gems(specs)
        GemRegistry::NOTABLE_GEMS.filter_map do |gem_name, info|
          next unless specs.key?(gem_name)

          {
            name: gem_name,
            version: specs[gem_name],
            category: info[:category].to_s,
            note: info[:note]
          }
        end
      end
    end
  end
end
