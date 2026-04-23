# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers test infrastructure: framework, factories/fixtures,
    # system tests, helpers, CI config, coverage.
    class TestIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call
        {
          framework: detect_framework,
          factories: detect_factories,
          fixtures: detect_fixtures,
          system_tests: detect_system_tests,
          test_helpers: detect_test_helpers,
          vcr_cassettes: detect_vcr,
          ci_config: detect_ci,
          coverage: detect_coverage
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def root
        app.root.to_s
      end

      def detect_framework
        if Dir.exist?(File.join(root, 'spec'))
          'rspec'
        elsif Dir.exist?(File.join(root, 'test'))
          'minitest'
        else
          'unknown'
        end
      end

      def detect_factories
        dirs = [
          File.join(root, 'spec/factories'),
          File.join(root, 'test/factories')
        ]

        dirs.each do |dir|
          next unless Dir.exist?(dir)

          count = Dir.glob(File.join(dir, '**/*.rb')).size
          return { location: dir.sub("#{root}/", ''), count: count } if count.positive?
        end

        nil
      end

      def detect_fixtures
        dirs = [
          File.join(root, 'spec/fixtures'),
          File.join(root, 'test/fixtures')
        ]

        dirs.each do |dir|
          next unless Dir.exist?(dir)

          count = Dir.glob(File.join(dir, '**/*.yml')).size
          return { location: dir.sub("#{root}/", ''), count: count } if count.positive?
        end

        nil
      end

      def detect_system_tests
        dirs = [
          File.join(root, 'spec/system'),
          File.join(root, 'test/system')
        ]

        dirs.filter_map do |dir|
          next unless Dir.exist?(dir)

          count = Dir.glob(File.join(dir, '**/*.rb')).size
          { location: dir.sub("#{root}/", ''), count: count } if count.positive?
        end.first
      end

      def detect_test_helpers
        dirs = [
          File.join(root, 'spec/support'),
          File.join(root, 'test/helpers')
        ]

        dirs.filter_map do |dir|
          next unless Dir.exist?(dir)

          Dir.glob(File.join(dir, '**/*.rb')).map { |f| f.sub("#{root}/", '') }
        end.flatten.sort
      end

      def detect_vcr
        dirs = [
          File.join(root, 'spec/cassettes'),
          File.join(root, 'spec/vcr_cassettes'),
          File.join(root, 'test/cassettes'),
          File.join(root, 'test/vcr_cassettes')
        ]

        dirs.each do |dir|
          next unless Dir.exist?(dir)

          count = Dir.glob(File.join(dir, '**/*.yml')).size
          return { location: dir.sub("#{root}/", ''), count: count } if count.positive?
        end

        nil
      end

      def detect_ci
        configs = []
        configs << 'github_actions' if Dir.exist?(File.join(root, '.github/workflows'))
        configs << 'circleci' if File.exist?(File.join(root, '.circleci/config.yml'))
        configs << 'gitlab_ci' if File.exist?(File.join(root, '.gitlab-ci.yml'))
        configs << 'travis' if File.exist?(File.join(root, '.travis.yml'))
        configs
      end

      def detect_coverage
        gemfile_lock = File.join(root, 'Gemfile.lock')
        return nil unless File.exist?(gemfile_lock)

        content = File.read(gemfile_lock)
        return 'simplecov' if content.include?('simplecov (')

        nil
      rescue StandardError
        nil
      end
    end
  end
end
