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
      # Returns +{ error: message }+ for any rescued +StandardError+ — including a
      # missing or unreadable lockfile, malformed content, or any other runtime
      # exception — so callers always receive a controlled hash rather than an
      # unhandled exception.
      #
      # @return [Hash] gem analysis with +:total_gems+, +:ruby_version+,
      #   +:notable_gems+, and +:categories+ on success; or +{ error: String }+ on
      #   any rescued +StandardError+
      def call
        lock_path = gemfile_lock_path
        return { error: 'No Gemfile.lock found' } unless File.exist?(lock_path)

        gem_summary(parse_lockfile(lock_path))
      rescue StandardError => error
        { error: "GemIntrospector failed: #{error.class}" }
      end

      private

      def gemfile_lock_path
        File.join(app.root, 'Gemfile.lock')
      end

      def gem_summary(specs)
        GemSummary.new(specs, detect_notable_gems(specs)).to_h
      end

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
            category: info[:category].to_s, # NOTABLE_GEMS uses Symbol categories; callers expect String keys
            note: info[:note]
          }
        end
      end

      # Builds the compact gem payload returned by {GemIntrospector}.
      class GemSummary
        def initialize(specs, notable_gems)
          @specs = specs
          @notable_gems = notable_gems
        end

        # @return [Hash] compact gem metadata with notable gems grouped by category
        def to_h
          {
            total_gems: @specs.size,
            ruby_version: @specs['ruby']&.first,
            notable_gems: @notable_gems,
            categories: GemRegistry.categorize(@notable_gems)
          }
        end
      end
      private_constant :GemSummary
    end
  end
end
