# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    # Discovers custom rake tasks from lib/tasks/.
    class RakeTaskIntrospector
      attr_reader :app

      def initialize(app)
        @app = app
      end

      def call
        tasks_dir = File.join(app.root.to_s, 'lib/tasks')
        return { tasks: [] } unless Dir.exist?(tasks_dir)

        tasks = Dir.glob(File.join(tasks_dir, '**/*.rake')).flat_map do |path|
          parse_rake_file(path, tasks_dir)
        end

        { tasks: tasks }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def parse_rake_file(path, base_dir)
        content = File.read(path)
        relative = path.sub("#{base_dir}/", '')
        tasks = []
        last_desc = nil

        current_namespace = []
        namespace_indents = []
        content.each_line do |line|
          indent = line.match(/^(\s*)/)[1].length

          if (ns_match = line.match(/^\s*namespace\s+:(\w+)/))
            current_namespace.push(ns_match[1])
            namespace_indents.push(indent)
          elsif line.match?(/^\s*end\b/) && namespace_indents.any? && indent <= namespace_indents.last
            current_namespace.pop
            namespace_indents.pop
          end

          if (desc_match = line.match(/desc\s+["'](.+?)["']/))
            last_desc = desc_match[1]
          end

          next unless (t_match = line.match(/^\s*task\s+:(\w+)/))

          name = (current_namespace + [t_match[1]]).join(':')
          tasks << {
            name: name,
            description: last_desc,
            file: relative
          }.compact
          last_desc = nil
        end

        tasks
      rescue StandardError => e
        [{ file: path.sub("#{base_dir}/", ''), error: e.message }]
      end
    end
  end
end
