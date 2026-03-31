# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Multi-Database section; returns nil when multi-db is not configured.
      class MultiDatabaseFormatter < SectionFormatter
        section :multi_database

        private

        def render(data)
          return unless data[:multi_db]

          lines = [ "## Multi-Database" ]
          if data[:databases]&.any?
            data[:databases].each do |db|
              replica = db[:replica] ? " (replica)" : ""
              lines << "- `#{db[:name]}` — #{db[:adapter]}#{replica}"
            end
          end

          if data[:model_connections]&.any?
            lines << "### Model Connections"
            data[:model_connections].each do |c|
              lines << "- `#{c[:model]}` → #{c[:connects_to] || 'custom connection'}"
            end
          end

          lines.join("\n")
        end
      end
    end
  end
end
